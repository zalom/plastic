# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkCompletionCheckTest < Plastic::TestCase
  SPEC = "# Spec\n\n## Done criteria\n- It works\n"

  def setup
    super
    @work = store_graphs.work
    @intent = open_intent
  end

  def check = Plastic::Graph::Work::Completion::Check.new(retrieval, "1")

  VERIFIED = "# Outcome\n\nDelivered.\n\n## Verification\n- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n"

  def files(spec: SPEC, outcome: VERIFIED)
    write("#{@intent.dir}/spec.md", spec)
    write("#{@intent.dir}/outcome.md", outcome) if outcome
    sync_up
  end

  def done_node(judge: "tests", findings: "green")
    @work.add_node(intent_id: "1", title: "Build")
    @work.claim_node(intent_id: "1", id: "n1", by: "a")
    @work.done_node(intent_id: "1", id: "n1", judge:, findings:)
  end

  def test_a_spec_with_criteria_a_verified_node_and_an_outcome_has_no_problem
    files
    done_node

    assert_empty check.problems
    assert_equal({ "It works" => "It works" }, check.criteria)
  end

  def test_an_intent_with_no_criteria_is_asked_for_them
    files(spec: "# Spec\n")
    done_node

    assert_equal ["Write the done criteria in spec.md and run plastic sync up."], check.problems
  end

  def test_open_decisions_ask_for_the_owner
    files(spec: "#{SPEC}\n## Open decisions\n- Which store?\n")
    done_node

    assert_equal ["Ask the owner to settle the open decisions and record the updated spec."], check.problems
  end

  def test_an_intent_with_no_live_node_asks_for_a_plan
    files

    assert_equal ["Plan at least one work node with plastic node add 1 TITLE --criterion TEXT."], check.problems
  end

  def test_an_unfinished_node_asks_for_the_work_to_finish
    files
    @work.add_node(intent_id: "1", title: "Build")

    assert_equal ["Finish every live work node before ending intent 1."], check.problems
  end

  def test_a_done_node_with_blank_findings_asks_for_the_verification
    files
    done_node(findings: " ")

    assert_match(/\AEvery done node needs a valid judge and nonempty findings/, check.problems.first)
  end

  def test_an_outcome_of_only_headings_asks_for_a_substantive_one
    files(outcome: "# Outcome\n## Summary\n")
    done_node

    assert_equal ["Write a substantive outcome.md in the intent folder and run plastic sync up."], check.record_problems
  end

  def test_the_outcome_hash_is_the_sha256_of_its_body
    files
    done_node

    assert_equal Digest::SHA256.hexdigest(VERIFIED), check.outcome_hash
  end

  def test_two_criteria_with_one_key_ask_for_distinct_keys
    files(spec: "## Done criteria\n- [ ] [same-key] One\n- [ ] [same-key] Two\n")
    done_node

    assert_equal ["Give each done criterion in spec.md its own key; same-key names two different criteria."], check.problems
  end

  def test_a_repeated_criterion_counts_once
    files(spec: "## Done criteria\n- It works\n- It works\n")
    done_node

    assert_equal [{ "It works" => "It works" }, []], [check.criteria, check.problems]
  end

  def test_an_outcome_without_a_merge_record_asks_for_it
    files(outcome: "# Outcome\n\nDelivered.\n\n## Verification\n- Architecture map: enola at abc123\n")
    done_node

    assert_equal 1, check.verification_problems.size
    assert_includes check.verification_problems.first, "Merged:"
    assert_empty check.record_problems
  end

  def test_an_outcome_without_a_map_record_asks_for_it
    files(outcome: "# Outcome\n\nDelivered.\n\n## Verification\n- Merged: plastic/1 into alpha at abc123\n")
    done_node

    assert_equal 1, check.verification_problems.size
    assert_includes check.verification_problems.first, "Architecture map:"
  end

  def test_the_problems_hold_the_record_and_the_verification_problems
    files(outcome: "# Outcome\n\nDelivered.\n")
    done_node

    assert_equal check.record_problems + check.verification_problems, check.problems
    assert_equal 2, check.problems.size
  end

  def test_abandon_problems_hold_only_the_outcome_substance
    files(spec: "# Spec\n", outcome: "# Outcome\n")

    assert_equal ["Write a substantive outcome.md in the intent folder and run plastic sync up."], check.abandon_problems
  end

  def test_the_attestation_keeps_each_key_with_its_text
    files(spec: "## Done criteria\n- [ ] [works] It works\n")
    done_node
    evidence = { "works" => "the tests pass" }

    assert_equal({ criteria: { "works" => "It works" }, evidence:, outcome_sha256: check.outcome_hash }, check.attestation(evidence))
  end
end
