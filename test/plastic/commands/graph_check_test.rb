# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/graph_check"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/edge_add"

class GraphCheckTest < Plastic::TestCase
  def call(*args) = plastic("graph", "check", *args, table: Plastic::CLI::TABLE)

  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def update_node(id, sql_set)
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:nodes, "UPDATE nodes SET #{sql_set} WHERE intent_id = '1' AND id = '#{id}'")
    end
  end

  def write_spec(intent, text)
    write("#{intent.dir}/spec.md", text)
    plastic("sync", "up", table: Plastic::CLI::TABLE)
  end

  def test_a_done_node_with_no_judge_is_a_finding
    open_intent
    add_node("a")
    update_node("n1", "state = 'done'")

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.out, "finding: node n1 is done with no judge"
  end

  def test_a_tests_judged_done_node_with_no_findings_is_a_finding
    open_intent
    add_node("a")
    update_node("n1", "state = 'done', judge = 'tests'")

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.out, "finding: node n1 judged by tests with no findings"
  end

  def test_an_isolated_node_in_a_graph_of_two_is_a_finding
    open_intent
    add_node("a")
    add_node("b")

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.out, "finding: node n1 has no edge"
    assert_includes result.out, "finding: node n2 has no edge"
  end

  def test_an_edge_clears_the_isolation_finding
    open_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    result = call("1")

    assert_equal 1, result.code
    assert_equal "finding: intent 1 names no done criterion\n", result.out
    assert_equal "plastic: code_check_graph, gate: see the findings above\n", result.err
  end

  def test_retries_over_the_cap_is_a_finding
    open_intent
    add_node("a")
    update_node("n1", "retries = 4")

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.out, "finding: node n1 retried 4 times"
  end

  def test_no_done_criterion_is_a_finding
    open_intent
    add_node("a")

    result = call("1")

    assert_includes result.out, "finding: intent 1 names no done criterion"
  end

  def test_a_tests_judged_done_node_with_findings_passes
    intent = open_intent
    add_node("a")
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")
    update_node("n1", "state = 'done', judge = 'tests', findings = 'green'")

    assert_equal 0, call("1").code
  end

  def test_a_clean_graph_passes
    intent = open_intent
    add_node("a")
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")

    result = call("1")

    assert_equal 0, result.code
    assert_includes result.out, "no findings"
  end
end
