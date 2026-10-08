# frozen_string_literal: true

require_relative "../../test_helper"

class IntentEndFixture < Plastic::TestCase
  CRITERION = "The delivery works"
  KEY = "delivery-works"
  VERIFICATION = "\n## Verification\n- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n"

  def cli(*args, session: "delivery")
    plastic(*args, table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => session })
  end

  def ready_intent(verification: VERIFICATION)
    intent = open_intent
    write("#{intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- [ ] [#{KEY}] #{CRITERION}\n")
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDelivered and verified.\n#{verification}")
    cli("sync", "up")
    cli("auto", "1")
    cli("node", "add", "1", "Deliver", "--criterion", CRITERION)
    cli("node", "claim", "1", "n1")
    cli("node", "done", "1", "n1", "--judge", "tests", "--findings", "Acceptance passes")
    intent
  end

  def evidence(intent, values = { KEY => "Acceptance passes in the target environment" })
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
    assert_equal({ KEY => CRITERION }, JSON.parse(row.fetch("criteria")))
    assert_equal Digest::SHA256.hexdigest("# Outcome\n\nDelivered and verified.\n#{VERIFICATION}"), row.fetch("outcome_sha256")
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

class IntentEndMergeCheckTest < IntentEndFixture
  def test_a_bare_end_asks_for_the_merge_and_the_architecture_map
    ready_intent(verification: "")

    result = cli("intent", "end", "1")

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "- Merged: "
    assert_includes result.out, "- Architecture map: "
  end

  def test_a_bare_end_without_the_records_closes_nothing
    ready_intent(verification: "")
    cli("intent", "end", "1")

    assert_equal "active", retrieval.intent("1").status
  end

  def test_a_submission_without_the_merge_record_hands_over_the_merge_check
    evidence(ready_intent(verification: "\n## Verification\n- Architecture map: enola at abc123\n"))

    result = finish

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "- Merged: "
    assert_includes result.out, "next: none"
  end

  def test_a_submission_without_the_merge_record_closes_nothing
    evidence(ready_intent(verification: "\n## Verification\n- Architecture map: enola at abc123\n"))
    finish

    assert_equal "active", retrieval.intent("1").status
  end

  def test_the_chain_has_no_problems
    assert_empty Plastic::Commands::IntentEnd.chain_problems
  end
end

class IntentEndAbandonTest < IntentEndFixture
  def droppable(outcome: "# Outcome\n\nDropped: the need went away.\n", **fields)
    intent = open_intent("Alpha", **fields)
    write("#{intent.dir}/outcome.md", outcome) if outcome
    cli("sync", "up")
    intent
  end

  def abandon(*extra) = cli("intent", "end", "1", "--abandoned", *extra)

  def test_abandoning_an_open_intent_with_only_an_outcome_closes_it
    droppable

    result = abandon

    assert_equal [0, "", "abandoned"], [result.code, result.err, retrieval.intent("1").status]
    assert_includes result.out, "intent: 1 abandoned"
    assert_includes result.out, "next: none"
  end

  def test_abandoning_sets_the_disposition_and_writes_no_completion
    droppable
    abandon

    assert_equal ["abandoned", nil], [retrieval.intent("1").disposition, retrieval.completion("1")]
  end

  def test_abandoning_a_future_intent_closes_it
    droppable(status: "future")

    assert_equal [0, "abandoned"], [abandon.code, retrieval.intent("1").status]
  end

  def test_abandoning_an_active_intent_releases_its_lock
    droppable
    cli("auto", "1")

    assert_equal [0, nil], [abandon.code, retrieval.lock("1")]
  end

  def test_repeating_the_abandon_cleans_its_lock
    droppable
    abandon
    store_graphs.work.take_lock("1", session_id: "delivery", mode: "auto")

    assert_equal [0, nil], [abandon.code, retrieval.lock("1")]
  end

  def test_an_abandon_after_a_delivered_handoff_abandons
    droppable
    cli("intent", "end", "1")

    assert_equal [0, "abandoned"], [abandon.code, retrieval.intent("1").status]
  end

  def test_abandoned_with_a_judge_is_a_usage_error
    droppable
    result = abandon("--judge", "agent")

    assert_equal 2, result.code
    assert_includes result.err, "--abandoned"
    assert_equal "open", retrieval.intent("1").status
  end

  def test_abandoned_with_evidence_is_a_usage_error
    droppable
    result = abandon("--evidence", "completion.json")

    assert_equal 2, result.code
    assert_includes result.err, "--abandoned"
  end

  def test_a_live_foreign_lock_refuses_the_abandon
    droppable
    store_graphs.work.take_lock("1", session_id: "someone-else", mode: "auto")

    assert_equal [3, "open"], [abandon.code, retrieval.intent("1").status]
  end

  def test_abandoning_without_an_outcome_fails
    droppable(outcome: nil)

    result = abandon

    assert_equal [1, "open"], [result.code, retrieval.intent("1").status]
    assert_includes result.out + result.err, "outcome.md"
  end

  def test_a_done_intent_cannot_be_abandoned
    open_intent(status: "done")

    assert_equal [1, "done"], [abandon.code, retrieval.intent("1").status]
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

  def test_the_missing_prerequisites_print_as_a_list
    intent = ready_intent
    evidence(intent)
    store_graphs.databases.fetch(:knowledge).transaction { |batch| batch.remove(:documents, intent_id: "1", path: "outcome.md") }

    result = finish

    assert_includes result.out, "Complete these recorded prerequisites: "
    refute_includes result.out, '["'
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
    write("#{intent.dir}/spec.md", "# Spec\n## Done criteria\n- [#{KEY}] #{CRITERION}\n## Open Questions\n- Which release?\n")
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
    write("#{other.dir}/evidence.json", JSON.generate({ KEY => "Checked" }))
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
