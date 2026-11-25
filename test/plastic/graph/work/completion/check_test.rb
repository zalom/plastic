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

  VERIFIED = "# Outcome\n\nDelivered.\n\n## Verification\n- Merged: plastic/1 into alpha at abc123\n"

  def files(spec: SPEC, outcome: VERIFIED)
    write("#{@intent.dir}/spec.md", spec)
    write("#{@intent.dir}/outcome.md", outcome) if outcome
    sync_up
  end

  def done_node(criterion: "It works", findings: "green")
    @work.add_node(intent_id: "1", title: "Build", criterion:)
    @work.claim_node(intent_id: "1", id: "n1", by: "a")
    @work.done_node(intent_id: "1", id: "n1", findings:)
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

    assert_equal ["Write the done criteria with plastic intent spec 1 --from FILE."], check.problems
  end

  def test_open_decisions_ask_for_the_owner
    files(spec: "#{SPEC}\n## Open decisions\n- Which store?\n")
    done_node

    assert_equal ["Ask the owner to settle the open decisions and record the updated spec."], check.problems
  end

  def test_an_intent_with_no_live_node_asks_for_a_plan
    files

    assert_equal ["Plan at least one work node with plastic node add 1 TITLE --criterion KEY.", "Cover every done criterion with a done node. No done node serves: It works."], check.problems
  end

  def test_an_unfinished_node_asks_for_the_work_to_finish
    files
    @work.add_node(intent_id: "1", title: "Build", criterion: "It works")

    assert_equal ["Finish every live work node before ending intent 1."], check.problems
  end

  def test_a_done_node_with_blank_findings_asks_for_the_verification
    files
    done_node(findings: " ")

    assert_match(/\AEvery done node needs nonempty findings/, check.problems.first)
  end

  def test_an_outcome_of_only_headings_asks_for_a_substantive_one
    files(outcome: "# Outcome\n## Summary\n")
    done_node

    assert_equal ["Write the summary of outcome.md with plastic intent outcome 1 --from FILE."], check.record_problems
  end

  def test_the_outcome_hash_is_the_sha256_of_its_body
    files
    done_node

    assert_equal Digest::SHA256.hexdigest(VERIFIED), check.outcome_hash
  end

  def test_two_criteria_with_one_key_ask_for_distinct_keys
    files(spec: "## Done criteria\n- [ ] [same-key] One\n- [ ] [same-key] Two\n")
    done_node(criterion: "same-key")

    assert_equal ["Give each done criterion in spec.md its own key; same-key names two different criteria."], check.problems
  end

  def test_a_repeated_criterion_counts_once
    files(spec: "## Done criteria\n- It works\n- It works\n")
    done_node

    assert_equal [{ "It works" => "It works" }, []], [check.criteria, check.problems]
  end

  def test_an_outcome_without_a_merge_record_asks_for_it
    files(outcome: "# Outcome\n\nDelivered.\n\n## Verification\n- Tests pass\n")
    done_node

    assert_equal 1, check.verification_problems.size
    assert_includes check.verification_problems.first, "--kind Merged"
    assert_empty check.record_problems
  end

  def test_an_outcome_without_a_map_record_asks_for_nothing_more
    files(outcome: "# Outcome\n\nDelivered.\n\n## Verification\n- Merged: plastic/1 into alpha at abc123\n")
    done_node

    assert_empty check.verification_problems
  end

  def test_the_problems_hold_the_record_and_the_verification_problems
    files(outcome: "# Outcome\n\nDelivered.\n")
    done_node

    assert_equal check.record_problems + check.verification_problems, check.problems
    assert_equal 1, check.problems.size
  end

  REASON = "Record why intent 1 is dropped with plastic intent note 1 'superseded by intent <id>' --kind Abandoned " \
    "or plastic intent note 1 'dropped because <reason>' --kind Abandoned."

  def test_abandon_problems_hold_the_outcome_summary_and_the_abandon_reason
    files(spec: "# Spec\n", outcome: "# Outcome\n")

    assert_equal ["Write the summary of outcome.md with plastic intent outcome 1 --from FILE.", REASON], check.abandon_problems
  end

  def test_an_abandon_reason_in_its_form_leaves_no_abandon_problem
    files(spec: "# Spec\n", outcome: "# Outcome\n\nDropped.\n\n## Verification\n- Abandoned: superseded by intent 4\n")

    assert_empty check.abandon_problems
  end

  def test_an_abandon_reason_out_of_its_form_is_quoted_before_the_fix
    files(spec: "# Spec\n", outcome: "# Outcome\n\nDropped.\n\n## Verification\n- Abandoned: superseded by intent <id>\n")

    assert_equal ["outcome.md says 'Abandoned: superseded by intent <id>', which is not an abandon reason in the form " \
      "'Abandoned: superseded by intent <id>' or 'Abandoned: dropped because <reason>'. #{REASON}"], check.abandon_problems
  end
end
