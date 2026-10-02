# frozen_string_literal: true

require_relative "../../test_helper"

class IntentEndFixture < Plastic::TestCase
  CRITERION = "The delivery works"

  def cli(*args, session: "delivery")
    plastic(*args, table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => session })
  end

  def ready_intent
    intent = open_intent
    write("#{intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- #{CRITERION}\n")
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDelivered and verified.\n")
    cli("sync", "up")
    cli("auto", "start", "1")
    cli("node", "add", "1", "Deliver", "--criterion", CRITERION)
    cli("node", "claim", "1", "n1")
    cli("node", "done", "1", "n1", "--judge", "tests", "--findings", "Acceptance passes")
    intent
  end

  def evidence(intent, values = { CRITERION => "Acceptance passes in the target environment" })
    write("#{intent.dir}/completion.json", JSON.generate(values))
  end

  def finish_ready_intent
    evidence(ready_intent)
    finish
  end

  def finish = cli("intent", "end", "1", "--judge", "agent", "--evidence", "completion.json")
end

class IntentEndTest < IntentEndFixture
  def test_closure_records_explicit_evidence_and_releases_the_lock
    intent = ready_intent
    evidence(intent)

    result = finish

    assert_equal 0, result.code
    assert_equal ["done", "delivered"], retrieval.intent("1").to_h.values_at(:status, :disposition)
    assert_nil retrieval.lock("1")
  end

  def test_closure_keeps_the_criterion_attestation_and_outcome_hash
    intent = ready_intent
    evidence(intent)
    finish
    row = retrieval.completion("1")

    assert_equal "agent", row.fetch("judge")
    assert_equal [CRITERION], JSON.parse(row.fetch("criteria"))
    assert_equal Digest::SHA256.hexdigest("# Outcome\n\nDelivered and verified.\n"), row.fetch("outcome_sha256")
  end

  def test_repeating_closure_keeps_the_first_record_and_cleans_its_lock
    finish_ready_intent
    before = retrieval.completion("1")
    store_graphs.work.take_lock("1", session_id: "delivery", mode: "auto")

    result = cli("intent", "end", "1")

    assert_equal 0, result.code
    assert_equal before, retrieval.completion("1")
    assert_nil retrieval.lock("1")
  end

  def test_without_attestation_hands_over_without_closing
    ready_intent

    result = cli("intent", "end", "1")

    assert_equal "active", retrieval.intent("1").status
    assert_includes result.out, "--evidence"
    assert_includes result.out, "next: none"
  end
end

class IntentEndRefusalTest < IntentEndFixture
  def test_missing_criterion_evidence_cannot_close
    intent = ready_intent
    evidence(intent, {})

    result = finish

    assert_equal 1, result.code
    assert_equal "active", retrieval.intent("1").status
  end

  def test_missing_outcome_cannot_close
    intent = ready_intent
    evidence(intent)
    store_graphs.databases.fetch(:knowledge).transaction { |batch| batch.remove(:documents, intent_id: "1", path: "outcome.md") }

    finish

    assert_equal "active", retrieval.intent("1").status
  end

  def test_a_live_foreign_lock_refuses_closure
    intent = ready_intent
    evidence(intent)
    store_graphs.work.take_lock("1", session_id: "someone-else", mode: "auto")

    result = finish

    assert_equal 3, result.code
    assert_equal "active", retrieval.intent("1").status
  end

  def test_evidence_outside_the_intent_is_refused
    ready_intent

    result = cli("intent", "end", "1", "--judge", "owner", "--evidence", "../../outside.json")

    assert_equal 1, result.code
    assert_equal "active", retrieval.intent("1").status
  end
end

class IntentEndPrerequisitesTest < IntentEndFixture
  def test_an_empty_graph_is_not_delivered
    intent = ready_intent
    evidence(intent)
    store_graphs.databases.fetch(:work).transaction { |batch| batch.remove(:nodes, intent_id: "1") }

    result = finish

    assert_includes result.out, "Plan at least one work node"
    assert_equal "active", retrieval.intent("1").status
  end

  def test_done_nodes_without_findings_are_not_accepted
    intent = ready_intent
    evidence(intent)
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.add("UPDATE nodes SET findings = NULL WHERE intent_id = '1'")
    end

    result = finish

    assert_includes result.out, "nonempty findings"
    assert_equal "active", retrieval.intent("1").status
  end

  def test_an_open_decision_prevents_closure
    intent = ready_intent
    evidence(intent)
    write("#{intent.dir}/spec.md", "# Spec\n## Done criteria\n- #{CRITERION}\n## Open Questions\n- Which release?\n")
    cli("sync", "up")

    result = finish

    assert_includes result.out, "settle the open decisions"
    assert_equal "active", retrieval.intent("1").status
  end

  def test_an_imported_done_intent_stays_closed_without_fabricated_evidence
    open_intent(status: "done")

    result = cli("intent", "end", "1")

    assert_equal 0, result.code
    assert_nil retrieval.completion("1")
    assert_includes result.out, "next: none"
  end

  def link_foreign_evidence(intent)
    other = open_intent("Other")
    write("#{other.dir}/evidence.json", JSON.generate({ CRITERION => "Checked" }))
    File.symlink(folder.path("#{other.dir}/evidence.json"), folder.path("#{intent.dir}/completion.json"))
  end

  def test_a_symlink_cannot_import_evidence_from_another_intent
    intent = ready_intent
    link_foreign_evidence(intent)

    result = finish

    assert_equal 1, result.code
    assert_equal "active", retrieval.intent("1").status
  end
end
