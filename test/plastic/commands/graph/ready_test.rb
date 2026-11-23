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
