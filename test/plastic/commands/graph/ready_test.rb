# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/graph/ready"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/edge/add"

class GraphReadyCaseTest < Plastic::TestCase
  def test_the_node_whose_needs_are_met_is_ready_and_offers_the_claim
    alpha_specified(TWO_CRITERIA)
    ran("intent approve 1", "node add 1 Build --criterion tests-pass", "node add 1 Test --criterion suite-green", "edge add 1 n2 n1")

    assert_case line("graph ready 1"), code: 0, out: ["ready: n2 Test", "next: plastic node claim 1 n2 --agent NAME"]
  end

  def test_an_intent_with_no_nodes_has_nothing_ready
    ran("intent new Alpha")

    assert_case line("graph ready 1"), code: 0, out: "because: no node is ready to claim\n"
  end

  def test_a_missing_intent_exits_1_and_names_it
    assert_case line("graph ready 9"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class GraphReadyTest < Plastic::TestCase
  def call(*args) = plastic("graph", "ready", *args, table: Plastic::CLI::TABLE)

  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def two_linked_nodes
    open_keyed_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)
  end

  def test_an_open_node_with_no_need_is_ready
    open_keyed_intent
    add_node("a")

    result = call("1")

    assert_equal 0, result.code
    assert_includes result.out, "ready: n1 a"
    assert_match(/^next: plastic node claim 1 n1 --agent NAME\b/, result.out)
  end

  def test_a_node_whose_need_is_not_done_is_not_ready
    two_linked_nodes

    result = call("1")

    assert_call result, code: 0, out: ["ready: n1 a"]
    refute_includes result.out, "ready: n2 b"
  end

  def test_claimed_work_leaves_nothing_ready_and_no_next_line
    two_linked_nodes
    plastic("node", "claim", "1", "n1", "--agent", "tester", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })
    plastic("node", "done", "1", "n1", "ok", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })
    plastic("node", "claim", "1", "n2", "--agent", "tester", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

    result = call("1")

    assert_equal [0, ""], [result.code, result.err]
    refute_match(/^next:/, result.out)
  end

  def ready_nodes_json = JSON.parse(call("1", "--json").out).dig("result", "nodes")

  def test_the_json_answer_carries_each_ready_node_as_fields
    open_keyed_intent
    add_node("a")

    assert_equal [{ "id" => "n1", "title" => "a", "kind" => "work", "criterion" => "done", "state" => "open", "needs" => [] }], ready_nodes_json
  end

  def test_the_json_answer_names_the_nodes_a_ready_node_needs
    two_linked_nodes
    plastic("node", "claim", "1", "n1", "--agent", "tester", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })
    plastic("node", "done", "1", "n1", "ok", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

    assert_equal [["n2", ["n1"]]], ready_nodes_json.map { |node| [node["id"], node["needs"]] }
  end

  def test_the_json_answer_keeps_the_text_lines_beside_the_nodes
    open_keyed_intent
    add_node("a")

    assert_equal ["ready: n1 a"], JSON.parse(call("1", "--json").out).dig("result", "output")
  end

  def test_the_json_answer_for_no_ready_node_carries_an_empty_list
    open_keyed_intent

    assert_equal [], ready_nodes_json
  end

  def test_the_text_answer_prints_no_node_fields
    open_keyed_intent
    add_node("a")

    assert_equal "ready: n1 a\n", call("1").out.lines.first
    refute_includes call("1").out, "criterion"
  end

  def test_claimed_work_says_why_nothing_is_ready
    two_linked_nodes
    plastic("node", "claim", "1", "n1", "--agent", "tester", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })
    plastic("node", "done", "1", "n1", "ok", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })
    plastic("node", "claim", "1", "n2", "--agent", "tester", table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => "s-1" })

    result = call("1")

    assert_includes result.out, "because: no node is ready to claim"
    refute_includes result.out, "ready:"
  end
end

# Done criteria of intent 513: a failed or parked node and what waits on it are named as the region to re-plan.
class GraphReadyRegionTest < Plastic::TestCase
  ENV_S = { "PLASTIC_SESSION" => "s-1" }.freeze

  def call(*args) = plastic("graph", "ready", *args, table: Plastic::CLI::TABLE)

  def step(*args) = plastic(*args, table: Plastic::CLI::TABLE, env: ENV_S)

  def chain
    open_keyed_intent
    %w[a b c d].each { |title| step("node", "add", "1", title, "--criterion", "done") }
    step("edge", "add", "1", "n1", "n2")
    step("edge", "add", "1", "n2", "n3")
  end

  def fail_first
    chain
    step("node", "claim", "1", "n1", "--agent", "tester")
    step("node", "fail", "1", "n1", "broke")
  end

  def test_a_failed_node_names_the_nodes_that_wait_on_it_transitively
    fail_first

    assert_includes call("1").out, "repair: n1 a is failed; waiting on it: n2 b, n3 c"
  end

  def test_a_node_that_does_not_depend_on_it_is_not_in_the_region
    fail_first

    refute_match(/waiting on it:.*n4/, call("1").out)
  end

  def test_a_failed_node_with_nothing_waiting_names_none
    open_keyed_intent
    step("node", "add", "1", "a", "--criterion", "done")
    step("node", "claim", "1", "n1", "--agent", "tester")
    step("node", "fail", "1", "n1", "broke")

    assert_includes call("1").out, "repair: n1 a is failed; nothing waits on it"
  end

  def test_a_parked_node_is_a_region_root
    chain
    step("node", "claim", "1", "n1", "--agent", "tester")
    step("node", "impede", "1", "n1", "blocked")

    assert_includes call("1").out, "repair: n1 a is impeded; waiting on it: n2 b, n3 c"
  end

  def test_a_node_that_is_done_is_left_out_of_the_region
    chain
    step("node", "claim", "1", "n1", "--agent", "tester")
    step("node", "done", "1", "n1", "ok")
    step("node", "claim", "1", "n2", "--agent", "tester")
    step("node", "fail", "1", "n2", "broke")

    assert_includes call("1").out, "repair: n2 b is failed; waiting on it: n3 c"
  end

  def test_with_nothing_ready_the_next_line_points_at_the_re_planning_commands
    open_keyed_intent
    step("node", "add", "1", "a", "--criterion", "done")
    step("node", "claim", "1", "n1", "--agent", "tester")
    step("node", "fail", "1", "n1", "broke")

    result = call("1")

    assert_match(/^next: plastic node add 1 TITLE --criterion KEY$/, result.out)
    assert_includes result.out, "because: node n1 is failed; re-plan it and what waits on it"
  end

  def test_a_ready_node_still_offers_its_claim_beside_the_region
    fail_first

    assert_match(/^next: plastic node claim 1 n4 --agent NAME$/, call("1").out)
  end

  def test_the_json_answer_carries_each_region
    fail_first

    repairs = JSON.parse(call("1", "--json").out).dig("result", "repairs")

    assert_equal [{ "id" => "n1", "title" => "a", "state" => "failed", "downstream" => [{ "id" => "n2", "title" => "b", "state" => "open" }, { "id" => "n3", "title" => "c", "state" => "open" }] }], repairs
  end

  def test_the_json_answer_carries_no_region_when_nothing_failed
    chain

    assert_equal [], JSON.parse(call("1", "--json").out).dig("result", "repairs")
  end

  def test_a_graph_with_nothing_failed_prints_no_repair_line
    chain

    refute_includes call("1").out, "repair:"
  end
end
