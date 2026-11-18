# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/claim"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/node/remove"
require_relative "../../../../lib/plastic/commands/node/done"
require_relative "../../../../lib/plastic/commands/node/ask"
require_relative "../../../../lib/plastic/commands/node/fail"
require_relative "../../../../lib/plastic/commands/node/release"
require_relative "../../../../lib/plastic/commands/edge/add"

class NodeClaimCaseTest < Plastic::TestCase
  def chained
    alpha_specified(TWO_CRITERIA)
    ran("intent approve 1", "node add 1 Build --criterion tests-pass", "node add 1 Test --criterion suite-green", "edge add 1 n2 n1")
  end

  def test_claiming_a_ready_node_prints_it_with_its_criterion_and_offers_done
    alpha_with_node

    assert_case line("node claim 1 n1"), code: 0,
      out: ["node: n1 Build", "criterion: tests-pass", "next: plastic node done 1 n1 TEXT"]
  end

  def test_claiming_the_node_whose_needs_are_met_prints_it_and_offers_done
    chained

    assert_case line("node claim 1 n2"), code: 0,
      out: ["node: n2 Test", "criterion: suite-green", "next: plastic node done 1 n2 TEXT"]
  end

  def test_claiming_a_node_that_needs_an_undone_node_exits_1_and_names_the_ready_list
    chained

    assert_case line("node claim 1 n1"), code: 1, out: "",
      err: ["node n1 needs a node that is not done; plastic graph ready 1 lists the nodes to claim"]
  end

  def test_claiming_in_a_missing_intent_exits_1_and_names_it
    assert_case line("node claim 9 n1"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class NodeClaimTest < Plastic::TestCase
  def test_the_claim_offers_the_text_and_no_judge
    open_intent
    add_node("a")

    out = claim("n1").out

    assert_includes out, "plastic node done 1 n1 TEXT"
    refute_includes out, "--judge"
  end

  def add_node(title)
    write("store/1--alpha/spec.md", "# Spec\n\n## Done criteria\n- [done] Done\n")
    sync_up
    store_graphs.work.approve_intent("1") unless structure.approval("1")
    plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)
  end

  def two_linked_nodes
    open_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)
  end

  def claim(*args) = plastic("node", "claim", "1", *args, env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

  def test_the_brief_includes_the_last_reason
    open_intent
    add_node("a")
    claim("n1")
    plastic("node", "fail", "1", "n1", "boom", table: Plastic::CLI::TABLE)
    plastic("node", "release", "1", "n1", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_includes result.out, "last reason: boom"
    assert_equal 0, result.code
    assert_equal "", result.err
  end

  def fail_and_release
    claim("n1")
    plastic("node", "fail", "1", "n1", "boom", table: Plastic::CLI::TABLE)
    plastic("node", "release", "1", "n1", table: Plastic::CLI::TABLE)
  end

  def test_the_fourth_claim_moves_the_node_to_needs_info_and_keeps_its_findings
    open_intent
    add_node("a")
    3.times { fail_and_release }

    result = claim("n1")

    assert_equal 3, result.code
    node = store_graphs.retrieval.node("1", "n1")

    assert_equal "needs_info", node.state
    assert_equal "boom", node.reason
  end

  def test_claiming_a_node_that_needs_an_open_node_is_refused
    two_linked_nodes

    result = claim("n2")

    assert_equal 1, result.code
    assert_includes result.err, "node n2 needs a node that is not done"
    assert_empty result.out
  end

  def test_a_node_refused_for_its_needs_is_claimed_once_they_are_done
    two_linked_nodes
    claim("n2")
    claim("n1")
    plastic("node", "done", "1", "n1", "ok", table: Plastic::CLI::TABLE)

    result = claim("n2")

    assert_call result, code: 0, out: ["because: node n2 is claimed\n"]
    assert_equal "claimed", store_graphs.retrieval.node("1", "n2").state
  end

  def test_a_refused_claim_is_refused_again_on_the_next_call
    open_keyed_intent
    claim("n9")

    result = claim("n9")

    assert_equal [1, ""], [result.code, result.out]
    assert_includes result.err, "no node n9 in intent 1"
  end

  def test_the_brief_names_the_input_file
    open_intent
    write("store/1--alpha/spec.md", "# Spec\n\n## Done criteria\n- [done] Done\n")
    sync_up
    store_graphs.work.approve_intent("1") unless structure.approval("1")
    plastic("node", "add", "1", "a", "--criterion", "done", "--input", "docs/a.md", table: Plastic::CLI::TABLE)

    call = claim("n1")

    assert_equal [0, ""], [call.code, call.err]
    assert_includes call.out, "input: docs/a.md"
  end

  def unapproved_claim
    open_intent
    write("store/1--alpha/spec.md", "# Spec\n\n## Done criteria\n- [done] Done\n")
    sync_up
    plastic("node", "add", "1", "a", "--criterion", "done", table: Plastic::CLI::TABLE)
    claim("n1")
  end

  def test_a_claim_before_the_go_ahead_exits_3_and_names_the_approval
    result = unapproved_claim

    assert_equal 3, result.code
    assert_includes result.err, "intent 1 has no go-ahead; the owner approves it with plastic intent approve 1"
  end

  def test_a_claim_before_the_go_ahead_offers_no_next_command
    refute_match(/^next: /, unapproved_claim.out)
  end

  def test_a_claim_before_the_go_ahead_leaves_the_node_open
    unapproved_claim

    assert_equal "open", store_graphs.retrieval.node("1", "n1").state
  end
end

class NodeClaimRefusalTest < Plastic::TestCase
  def claim(*args) = plastic("node", "claim", "1", *args, env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

  def add_node(title)
    write("store/1--alpha/spec.md", "# Spec\n\n## Done criteria\n- [done] Done\n")
    sync_up
    store_graphs.work.approve_intent("1") unless structure.approval("1")
    plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)
  end

  def test_claiming_a_done_node_is_refused
    open_intent
    add_node("a")
    claim("n1")
    plastic("node", "done", "1", "n1", "ok", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_equal 1, result.code
    assert_empty result.out
    assert_equal "plastic: node n1 is done; it cannot move to claimed\n", result.err
  end

  def test_claiming_a_needs_info_node_is_refused
    open_intent
    add_node("a")
    claim("n1")
    plastic("node", "ask", "1", "n1", "which way?", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_equal 1, result.code
    assert_empty result.out
    assert_equal "plastic: node n1 is needs_info; it cannot move to claimed\n", result.err
  end

  def test_claiming_a_removed_node_is_refused
    open_intent
    add_node("a")
    plastic("node", "remove", "1", "n1", table: Plastic::CLI::TABLE)

    result = claim("n1")

    assert_equal 1, result.code
    assert_empty result.out
    assert_equal "plastic: node n1 is removed; it cannot move to claimed\n", result.err
  end

  def test_claiming_an_already_claimed_node_is_refused
    open_intent
    add_node("a")
    claim("n1")

    result = claim("n1")

    assert_equal [3, ""], [result.code, result.out]
    assert_includes result.err, "node n1 is held by session"
  end

  def test_a_claim_with_no_session_fails_and_names_the_variable
    open_intent
    add_node("a")

    result = plastic("node", "claim", "1", "n1", env: { "PLASTIC_SESSION" => "" }, table: Plastic::CLI::TABLE)

    assert_equal [1, "plastic: node claim names no session; set PLASTIC_SESSION\n"], [result.code, result.err]
  end
end
