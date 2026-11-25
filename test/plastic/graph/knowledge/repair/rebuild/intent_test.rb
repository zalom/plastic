# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/knowledge/repair/rebuild/intent"

# The records an old intent folder gives: nodes, packets, findings, log lines and rulings.
class RebuildIntentTest < Minitest::Test
  Intent = Plastic::Graph::Knowledge::Repair::Rebuild::Intent

  CHECKLIST = <<~MD
    - [x] ACTION_1 - first step
    - [ ] ACTION_2 - second step
    - [x] ACTION_1 - another part of the first

    ## Session Log
    | Date | Items Completed | Notes |
    |------|-----------------|-------|
    | 2026-07-02 | ACTION_1 | Done on the branch. |
  MD
  BRIEF = "# ACTION 1 - First\n\nDo the first thing.\n\n## Result\nIt works.\n"
  OTHER = "# Release notes brief\n\nWrite them.\n"
  PLAN = "# Plan\n\n## Approach\nSmall steps.\n\n## Decisions\n- Keep the old flag.\n- Ship it.\n\n## Steps\n1. Not used.\n"
  FILES = { "checklist.md" => CHECKLIST, "plan.md" => PLAN, "actions/ACTION_1.md" => BRIEF, "actions/reports.md" => OTHER, "actions/.gitkeep" => "" }.freeze

  def rebuild(status, files = FILES, held: "") = Intent.new("store/7--x", files, status:, held:)

  def test_the_checklist_items_give_the_nodes_in_order_with_their_states
    assert_equal [["ACTION_1 - first step", "done"], ["ACTION_2 - second step", "abandoned"], ["ACTION_1 - another part of the first", "done"]],
      rebuild("done").nodes.first(3).map { |node| [node.title, node.state] }
  end

  def test_an_unticked_step_stays_open_in_an_intent_that_is_not_closed
    assert_equal %w[done open done], rebuild("in_progress").nodes.first(3).map(&:state)
  end

  def test_a_brief_is_the_packet_of_each_step_it_names_and_its_result_the_findings
    nodes = rebuild("done").nodes

    assert_equal [BRIEF, nil, BRIEF], nodes.first(3).map(&:packet)
    assert_equal ["It works.", nil, "It works."], nodes.first(3).map { |node| node.findings if node.packet }
  end

  def test_a_brief_that_names_no_step_is_a_node_of_its_own_in_the_state_of_the_intent
    node = rebuild("done").nodes.last

    assert_equal ["Release notes brief", "done", OTHER], [node.title, node.state, node.packet]
  end

  def test_a_done_node_has_findings_and_an_abandoned_one_a_reason
    nodes = rebuild("done").nodes

    assert_equal [true, true], [nodes.select { |node| node.state == "done" }.none? { |node| node.findings.to_s.empty? }, !nodes[1].reason.to_s.empty?]
  end

  def test_the_plan_gives_the_steps_only_when_the_checklist_lists_none
    nodes = rebuild("done", { "plan.md" => PLAN, "checklist.md" => "# Checklist\n" }).nodes

    assert_equal [["Not used.", "abandoned"]], nodes.map { |node| [node.title, node.state] }
  end

  def test_each_session_log_row_is_a_dated_line
    line = rebuild("done").lines.first

    assert_equal ["2026-07-02T00:00:00Z", "Session log of 2026-07-02: ACTION_1. Done on the branch."], [line.at, line.text]
  end

  def test_the_approach_and_each_decision_the_store_lacks_are_rulings
    assert_equal ["Approach: Small steps.", "Keep the old flag.", "Ship it."], rebuild("done").rulings
  end

  def test_a_decision_the_spec_or_a_ruling_holds_is_not_ruled_again
    assert_equal ["Approach: Small steps.", "Ship it."], rebuild("done", held: "D1: Keep the old flag.").rulings
  end

  def test_the_files_the_rebuild_reads_are_those_of_its_records
    assert_equal %w[actions/ACTION_1.md actions/reports.md checklist.md plan.md], rebuild("done").rebuilt
  end

  def test_a_placeholder_gives_no_record
    files = { "checklist.md" => "<!-- plastic:placeholder -->\n- [ ] ...\n", "plan.md" => "<!-- plastic:placeholder -->\n" }
    rebuild = rebuild("future", files)

    assert_equal [[], [], []], [rebuild.nodes, rebuild.lines, rebuild.rulings]
  end

  def test_an_evidence_file_that_names_no_step_is_a_node_of_its_own_with_findings
    table = "# Resume restoration\n\n| Requirement | Evidence | Result |\n| --- | --- | --- |\n| a | b | c |\n"
    node = rebuild("done", { "actions/01-restoration.md" => table }).nodes.first

    assert_equal ["Resume restoration", "done", table, nil], [node.title, node.state, node.findings, node.packet]
  end

  def test_a_ticked_step_takes_the_text_of_an_evidence_file_that_names_it_as_findings
    table = "# ACTION 1 proof\n\n| Requirement | Evidence | Result |\n| --- | --- | --- |\n| a | b | c |\n"
    files = { "checklist.md" => "- [x] ACTION_1 - first\n", "actions/ACTION_1.md" => table }

    assert_equal table, rebuild("done", files).nodes.first.findings
  end

  def test_an_intent_that_has_graph_nodes_gets_no_node_but_keeps_its_lines_and_rulings
    graphed = Intent.new("store/7--x", FILES, status: "done", held: "", graphed: true)

    assert_equal [[], 1, 3], [graphed.nodes, graphed.lines.size, graphed.rulings.size]
  end

  def test_a_log_row_with_text_after_its_date_keeps_the_text_in_its_line
    files = { "checklist.md" => "## Session Log\n| Date | Items | Notes |\n|--|--|--|\n| 2026-07-11 (fix round 1) | a | b |\n" }

    assert_equal "Session log of 2026-07-11 (fix round 1): a. b", rebuild("done", files).lines.first.text
  end
end
