# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/show_brief"

class ShowBriefTest < Plastic::TestCase
  def brief(intent_id = "1") = run_workflow(Plastic::Workflows::ShowBrief, intent_id:)

  def test_an_intent_without_a_goal_is_briefed_by_its_title
    open_intent

    _outcome, context = brief

    assert_equal "goal: Alpha", context.printed.first
  end

  def test_the_goal_and_criteria_come_from_the_spec
    write("#{open_intent.dir}/spec.md", "# Spec\n\n## Goal\n- Ship it\n\n## Done criteria\n- It works\n")
    sync_up

    printed = brief.last.printed

    assert_equal ["goal: Ship it", "criterion: It works"], printed.grep(/\A(goal|criterion):/)
  end

  def spec_line(context) = context.printed.find { |line| line.start_with?("spec:") }

  def test_the_brief_says_who_writes_the_spec_and_names_the_criteria_heading
    open_intent

    line = spec_line(brief.last)

    assert_includes line, "none yet; the agent writes"
    assert_includes line, '"## Done criteria"'
  end

  def test_the_brief_of_an_intent_with_a_spec_names_the_file_and_the_criteria_heading
    intent = open_intent
    write("#{intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- It works\n")
    sync_up

    assert_equal "spec: #{intent.dir}/spec.md; the done criteria are the bullets under its \"## Done criteria\" heading", spec_line(brief.last)
  end

  def test_superseded_rulings_and_ready_nodes_are_listed
    open_intent
    store_graphs.work.add_ruling(intent_id: "1", text: "Old")
    store_graphs.work.add_ruling(intent_id: "1", text: "New", supersedes: "1/D1")
    store_graphs.work.add_node(intent_id: "1", title: "Build")

    printed = brief.last.printed

    assert_equal ["ruling: D1 Old (superseded)", "ruling: D2 New", "ready: n1 Build"], printed.grep(/\A(ruling|ready):/)
  end

  def test_the_node_and_edge_usage_closes_the_brief
    open_intent

    assert_equal Plastic::Commands::EdgeRemove.usage_line, brief.last.printed.last
  end

  def test_an_unknown_intent_fails_the_call
    assert_equal "code_show_brief, gate: no intent 9 in this store", brief("9").first.message
  end
end
