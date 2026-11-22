# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/graph/check"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/edge/add"

class GraphCheckCaseTest < Plastic::TestCase
  def test_checking_a_missing_intent_exits_1_and_names_it
    assert_case line("graph check 9"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

module GraphCheckSupport
  def call(*args) = plastic("graph", "check", *args, table: Plastic::CLI::TABLE)

  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def update_node(id, sql_set)
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.write(:nodes, "UPDATE nodes SET #{sql_set} WHERE intent_id = '1' AND id = '#{id}'")
    end
  end

  def add_runs(id, count)
    store_graphs.databases.fetch(:store).transaction do |batch|
      (1..count).each do |number|
        batch.put(:runs, { intent_id: "1", node_id: id, number:, agent: "", session_id: "s-1", started_at: "2026-11-17T01:00:00Z", ended_at: "2026-11-17T01:01:00Z", result: "failed" })
      end
    end
  end

  def write_spec(intent, text)
    write("#{intent.dir}/spec.md", text)
    plastic("sync", "up", table: Plastic::CLI::TABLE)
  end
end

class GraphCheckTest < Plastic::TestCase
  include GraphCheckSupport

  def test_a_done_node_with_no_findings_is_a_finding
    open_keyed_intent
    add_node("a")
    update_node("n1", "state = 'done'")

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.out, "finding: node n1 is done with no findings"
  end

  def test_an_isolated_node_in_a_graph_of_two_is_a_finding
    open_keyed_intent
    add_node("a")
    add_node("b")

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.out, "finding: node n1 has no edge"
    assert_includes result.out, "finding: node n2 has no edge"
  end

  def test_an_edge_clears_the_isolation_finding
    intent = open_keyed_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)
    write_spec(intent, "# Spec\n")

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.out, "finding: intent 1 names no done criterion\n"
    assert_equal "plastic: see the findings above\n", result.err
  end

  def test_retries_over_the_cap_is_a_finding
    open_keyed_intent
    add_node("a")
    add_runs("n1", 4)

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.out, "finding: node n1 retried 4 times"
  end

  def test_no_done_criterion_is_a_finding
    intent = open_keyed_intent
    add_node("a")
    write_spec(intent, "# Spec\n")

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.out, "finding: intent 1 names no done criterion"
    assert_equal "plastic: see the findings above\n", result.err
  end

  def test_a_done_node_with_findings_passes
    intent = open_keyed_intent
    add_node("a")
    write_spec(intent, "# Spec\n\n## Done criteria\n- [done] ships\n")
    update_node("n1", "state = 'done', findings = 'green'")

    assert_equal 0, call("1").code
  end

  def test_a_clean_graph_passes
    intent = open_keyed_intent
    add_node("a")
    write_spec(intent, "# Spec\n\n## Done criteria\n- [done] ships\n")

    result = call("1")

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "no findings"
    assert_match(/^next: plastic node claim 1 n1\b/, result.out)
  end

  def test_a_clean_graph_offers_the_first_ready_node
    intent = open_keyed_intent
    add_node("a")
    write_spec(intent, "# Spec\n\n## Done criteria\n- [done] ships\n")

    result = call("1")

    assert_match(/^next: plastic node claim 1 n1\b/, result.out)
  end

  def test_a_clean_intent_with_no_ready_node_has_no_next_line_and_a_reason
    intent = open_keyed_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- [done] ships\n")

    result = call("1")

    assert_equal [0, ""], [result.code, result.err]
    refute_match(/^next:/, result.out)
  end

  def test_a_clean_intent_with_no_ready_node_says_why_and_does_not_replan
    intent = open_keyed_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- [done] ships\n")

    result = call("1")

    assert_includes result.out, "because: no node is ready to claim"
    refute_includes result.out, "Before you plan"
  end
end

class GraphCheckRepairTest < Plastic::TestCase
  include GraphCheckSupport

  def test_each_finding_is_followed_by_its_repair_command
    open_keyed_intent
    add_node("a")
    add_node("b")

    out = call("1").out

    assert_includes out, "finding: node n1 has no edge\nrepair: plastic edge add 1 n1 TO\n"
    assert_includes out, "finding: node n2 has no edge\nrepair: plastic edge add 1 n2 TO\n"
  end

  def test_the_next_line_is_the_first_repair_and_the_because_line_says_to_check_again
    open_keyed_intent
    add_node("a")
    add_node("b")

    out = call("1").out

    assert_match(/^next: plastic edge add 1 n1 TO$/, out)
    assert_match(/^because: .*run plastic graph check 1 again/, out)
  end

  def test_a_need_on_a_removed_node_is_a_finding_with_its_repair
    intent = open_keyed_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)
    write_spec(intent, "# Spec\n\n## Done criteria\n- [done] ships\n")
    update_node("n1", "state = 'removed'")

    out = call("1").out

    assert_includes out, "finding: node n2 needs n1, which is removed\nrepair: plastic edge remove 1 n1 n2\n"
    assert_match(/^next: plastic edge remove 1 n1 n2$/, out)
  end

  def test_a_loop_from_a_hand_edited_graph_is_a_finding_with_its_repair
    intent = open_keyed_intent
    add_node("a")
    add_node("b")
    store_graphs.databases.fetch(:store).transaction do |batch|
      [%w[n1 n2], %w[n2 n1]].each { |from, to| batch.put(:edges, { intent_id: "1", from:, to:, kind: "needs" }, statement: :insert) }
    end
    write_spec(intent, "# Spec\n\n## Done criteria\n- [done] ships\n")

    out = call("1").out

    assert_includes out, "finding: nodes loop: n1 -> n2 -> n1\nrepair: plastic edge remove 1 n2 n1\n"
  end

  def json_answer
    open_keyed_intent
    add_node("a")
    add_node("b")
    JSON.parse(call("1", "--json").out)
  end

  def test_the_json_answer_names_no_internal_workflow_name
    document = json_answer

    assert_equal "see the findings above", document.dig("result", "error", "message")
    refute_includes document.to_json, "code_check_graph"
  end

  def test_the_json_answer_carries_the_repairs_and_the_first_one_as_next
    document = json_answer

    assert_equal "plastic edge add 1 n1 TO", document.fetch("next")
    assert_includes document.dig("result", "output"), "repair: plastic edge add 1 n1 TO"
  end
end
