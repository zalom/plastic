# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/add"

class NodeAddCaseTest < Plastic::TestCase
  def test_a_node_with_an_input_path_prints_its_id_and_offers_the_edge
    alpha_specified

    assert_case line("node add 1 Build --criterion tests-pass --input docs/plan.md"), code: 0,
      out: ["node: n1", "next: plastic edge add 1 FROM TO"]
  end
end

class NodeAddTest < Plastic::TestCase
  include LifecycleHelper

  def call(*args) = plastic("node", "add", *args, table: Plastic::CLI::TABLE)

  def nodes = work_rows("nodes")

  def test_missing_criterion_exits_2
    specified

    result = call("1", "do the thing")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "missing --criterion"
    assert_empty nodes
  end

  def test_a_known_key_writes_the_node_with_the_key
    specified

    result = call("1", "do the thing", "--criterion", KEY)

    assert_call result, code: 0, err: "", out: ["node: n1", "next: plastic edge add 1 FROM TO"]
    assert_equal [KEY], nodes.map { |row| row.fetch("criterion") }
  end

  def test_the_next_line_offers_the_edge_add_command_and_the_because_names_graph_check
    specified

    out = call("1", "do the thing", "--criterion", KEY).out

    assert_match(/^next: plastic edge add 1 FROM TO/, out)
    assert_match(/^because:.*then run plastic graph check 1/, out)
  end

  def test_the_because_line_says_what_an_edge_means
    specified

    out = call("1", "do the thing", "--criterion", KEY).out

    assert_match(/^because:.*an edge FROM TO means TO reads, changes or tests what FROM makes/, out)
  end

  def test_two_nodes_read_n1_and_n2
    specified

    call("1", "first", "--criterion", KEY)

    assert_includes call("1", "second", "--criterion", KEY).out, "node: n2"
  end

  def test_an_unknown_key_exits_1_naming_the_keys_the_spec_has_and_writes_no_node
    specified({ KEY => CRITERION, "other" => "Another" })

    result = call("1", "do the thing", "--criterion", "nope")

    assert_call result, code: 1, err: ["works", "other", "criterion \"nope\" is not a done criterion key of spec.md"]
    refute_match(/^next:/, result.out)
    assert_empty nodes
  end

  def test_the_criterion_text_is_not_a_key
    specified

    assert_equal [1, []], [call("1", "do the thing", "--criterion", CRITERION).code, nodes]
  end

  def test_no_spec_exits_1_saying_to_write_the_done_criteria_with_the_spec_command
    open_intent

    result = call("1", "do the thing", "--criterion", KEY)

    assert_equal 1, result.code
    assert_includes result.err, "intent 1 has no spec.md; write its done criteria with plastic intent spec 1 --from FILE"
    assert_empty nodes
  end

  def test_refused_on_a_done_intent
    open_intent(status: "done")

    assert_equal 3, call("1", "do the thing", "--criterion", KEY).code
  end

  def test_refused_on_a_missing_intent
    result = call("9", "do the thing", "--criterion", KEY)

    assert_equal [1, ""], [result.code, result.out]
    assert_includes result.err, "no intent 9 in this store"
  end

  def test_takes_the_intent_as_its_subject
    assert_equal [:intent_id], Plastic::Commands::Node::Add.subject
  end
end

class NodeAddInputTest < Plastic::TestCase
  include LifecycleHelper

  def call(*args) = plastic("node", "add", *args, table: Plastic::CLI::TABLE)

  def nodes = work_rows("nodes")

  def input_rows = work_rows("node_inputs").sort_by { |row| row.fetch("position") }.map { |row| row.values_at("node_id", "position", "path") }

  def test_two_input_paths_are_stored_in_the_order_given
    specified

    result = call("1", "do the thing", "--criterion", KEY, "--input", "docs/b.md", "--input", "docs/a.md")

    assert_call result, code: 0, err: "", out: ["node: n1", "next: plastic edge add 1 FROM TO"]
    assert_equal [["n1", 1, "docs/b.md"], ["n1", 2, "docs/a.md"]], input_rows
  end

  def test_one_input_path_is_stored_as_the_first_position
    specified
    call("1", "do the thing", "--criterion", KEY, "--input", "docs/a.md")

    assert_equal [["n1", 1, "docs/a.md"]], input_rows
  end

  def test_a_node_with_no_input_path_stores_no_row
    specified
    call("1", "do the thing", "--criterion", KEY)

    assert_empty input_rows
  end

  def test_a_path_given_twice_is_stored_as_given_in_its_place
    specified
    call("1", "do the thing", "--criterion", KEY, "--input", "a.md", "--input", "a.md")

    assert_equal [["n1", 1, "a.md"], ["n1", 2, "a.md"]], input_rows
  end

  def empty_input_call
    specified
    call("1", "do the thing", "--criterion", KEY, "--input", "docs/a.md", "--input", "")
  end

  def test_an_empty_input_path_exits_2_naming_the_option
    result = empty_input_call

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "--input"
  end

  def test_an_empty_input_path_writes_no_node_and_no_input_row
    empty_input_call

    assert_equal [[], []], [nodes, input_rows]
  end

  def test_the_nodes_table_has_no_input_column
    specified
    call("1", "do the thing", "--criterion", KEY, "--input", "docs/a.md")

    refute_includes nodes.first.keys, "input"
  end
end
