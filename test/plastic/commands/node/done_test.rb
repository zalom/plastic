# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/done"

class NodeDoneCaseTest < Plastic::TestCase
  def test_finishing_a_node_nobody_claimed_exits_3_and_names_its_status
    alpha_with_node(approved: false)

    assert_case line('node done 1 n1 "Example verification"'), code: 3, out: "", err: ["node n1 is open; it cannot move to done"]
  end
end

class NodeDoneTest < Plastic::TestCase
  include LifecycleHelper

  USAGE = "plastic node done ID NODE TEXT\n"

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("intent", "start", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "claim", "1", "n1")
  end

  def test_finishing_a_claimed_node_offers_the_ready_set
    result = cli("node", "done", "1", "n1", "ok")

    assert_call result, code: 0, out: "node: n1 done\nwrote:  1 node and 1 work log line in work_graph.db\nfiles:  store/1--alpha/work.log\n        store/1--alpha/graph.json\n\nnext: plastic graph ready 1\nbecause: node n1 is done\n"
  end

  def test_findings_that_hold_column_names_are_stored_unchanged
    cli("node", "done", "1", "n1", "see :id and :intent_id")

    assert_equal "see :id and :intent_id", retrieval.node("1", "n1").findings
  end

  def test_the_usage_line_has_the_text_and_the_file_option
    assert_includes Plastic::Commands::Node::Done.usage_line("node done"), "--file PATH"
  end

  def heads = store_database.rows("SELECT path FROM document_heads WHERE path LIKE '_.md'").map { |row| row.fetch("path") }

  def test_file_option_limits_the_read_to_that_file
    cli("node", "add", "1", "Second", "--criterion", KEY)
    cli("node", "claim", "1", "n2")
    dir = retrieval.intent("1").dir
    write("#{dir}/a.md", "# a\n")
    write("#{dir}/b.md", "# b\n")

    assert_call cli("node", "done", "1", "n1", "ok", "--file", "a.md"), code: 0, out: /node: n1 done/
    assert_equal ["a.md"], heads
  end

  def test_two_claimed_nodes_each_finish_with_their_own_file
    cli("node", "add", "1", "Second", "--criterion", KEY)
    cli("node", "claim", "1", "n2")
    dir = retrieval.intent("1").dir
    write("#{dir}/a.md", "# a\n")
    write("#{dir}/b.md", "# b\n")
    cli("node", "done", "1", "n1", "ok", "--file", "a.md")
    after_first = heads
    cli("node", "done", "1", "n2", "ok", "--file", "b.md")

    assert_equal [%w[a.md], %w[a.md b.md]], [after_first, heads.sort]
  end

  def test_a_file_the_sync_does_not_read_exits_2_naming_it_and_the_node_stays_claimed
    dir = retrieval.intent("1").dir
    write("#{dir}/resources/tmp/scratch.md", "# scratch\n")
    result = cli("node", "done", "1", "n1", "ok", "--file", "resources/tmp/scratch.md")

    assert_call result, code: 2, err: /resources\/tmp\/scratch\.md/
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_a_file_outside_the_intent_exits_2_and_the_node_stays_claimed
    result = cli("node", "done", "1", "n1", "ok", "--file", "../elsewhere.md")

    assert_equal 2, result.code
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_without_the_file_option_every_changed_file_is_read
    dir = retrieval.intent("1").dir
    write("#{dir}/a.md", "# a\n")
    write("#{dir}/b.md", "# b\n")
    cli("node", "done", "1", "n1", "ok")

    assert_equal %w[a.md b.md], heads.sort
  end

  def test_the_judge_option_is_a_usage_error_and_the_node_stays_claimed
    result = cli("node", "done", "1", "n1", "--judge", "tests", "ok")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "invalid option: --judge"
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_empty_findings_exit_2_and_leave_the_node_claimed
    result = cli("node", "done", "1", "n1", "")

    assert_call result, code: 2, err: /TEXT/
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_blank_findings_exit_2_and_leave_the_node_claimed
    result = cli("node", "done", "1", "n1", " ")

    assert_call result, code: 2, err: /TEXT/
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_missing_findings_exit_2_and_leave_the_node_claimed
    result = cli("node", "done", "1", "n1")

    assert_call result, code: 2, err: /TEXT/
    assert_equal "claimed", retrieval.node("1", "n1").state
  end

  def test_a_second_call_by_the_holder_exits_zero_and_keeps_the_findings_of_the_first
    cli("node", "done", "1", "n1", "first")

    result = cli("node", "done", "1", "n1", "Rechecked the target")

    assert_call result, code: 0, out: ["node: n1 done"]
    assert_equal ["done", "first"], retrieval.node("1", "n1").to_h.values_at(:state, :findings)
  end
end
