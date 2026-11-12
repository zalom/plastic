# frozen_string_literal: true

require_relative "../../../command_reference_helper"

class CommandReferenceMarkdownEventsTest < Minitest::Test
  include CommandReferenceHelper

  def text(words) = CommandReference::Markdown::Page.new(page(words)).to_s

  def events(words) = text(words)[/## The events of one call.*?(?=\n## What one call reads)/m]

  def items(words) = events(words).lines.grep(/^\d+\. /).map(&:chomp)

  def subsection(words, title) = events(words)[/^### #{Regexp.escape(title)}\n.*?(?=\n### |\n## |\z)/m]

  def test_one_workflow_tells_each_row_and_outcome_as_a_numbered_item_with_its_code_link
    list = items("intent new")

    assert_equal 6, list.size
    assert_equal %w[Read Gate Step Step Read Outcome], list.map { |item| item[/\A\d+\. (\w+)/, 1] }
    list.each { |item| assert_match(/\.rb#L\d+\)\z/, item) }
  end

  def test_a_gate_item_says_its_check_and_its_exit
    gate = items("intent new")[1]

    assert_includes gate, "`context.problem.nil?`"
    assert_includes gate, "exit 1"
    assert_includes gate, "prints PROBLEM"
  end

  def test_a_step_item_says_its_done_check
    step = items("intent new")[2]

    assert_includes step, "Step: write the intent. Done when `!context.intent_id.nil?`, so a second call skips it."
  end

  def test_a_check_with_a_pipe_stays_in_its_code_span
    item = items("intent new")[3]

    assert_includes item, "`context.after.nil? || !context.linked.nil?`"
  end

  def test_an_outcome_item_says_when_it_finishes_and_what_comes_next
    assert_includes items("intent new").last, "Outcome `:done`, always: finishes with exit 0; next: plastic next."
  end

  def test_one_workflow_without_an_own_call_builds_no_workflows_figure
    refute_includes text("intent new"), "workflows.svg"
    assert_includes text("intent new"), "(code_write_intent.svg)"
    assert_includes text("intent new"), "The call starts the workflow `Code::Intent::New`"
  end

  def test_several_workflows_show_the_workflows_figure_before_one_subsection_each
    body = events("auto")

    assert_operator body.index("workflows.svg"), :<, body.index("### ")
    assert_operator body.index("### Code::Auto::Pick"), :<, body.index("### Code::Auto\n")
    assert_includes body, "| Workflow | Kind | Code |"
  end

  def test_an_outcome_that_runs_another_workflow_starts_it_by_link
    assert_includes events("auto"), "starts the workflow [Code::Auto](#codeauto)"
  end

  def test_a_routine_with_its_own_call_tells_it_before_the_first_workflow
    body = events("update")

    assert_operator body.index("### The command's own call"), :<, body.index("### Code::")
    assert_includes body, "The command's own `call`"
  end

  def test_a_one_workflow_command_tells_its_own_call_before_the_workflow
    body = events("intent note")

    assert_operator body.index("### The command's own call"), :<, body.index("### Code::")
  end

  def test_an_agent_workflow_tells_the_hand_off_and_what_the_next_call_resumes
    section = subsection("intent end", "Agent::Intent::End")

    ["hands off", "exit 0", "routine run", "local.db"].each { |part| assert_includes section, part }
  end

  def test_a_read_only_agent_command_says_the_next_call_starts_fresh
    words = Plastic::CLI::TABLE.keys.find { |each| page(each).flows.any?(&:agent?) && page(each).klass.writes.empty? }
    body = events(words)

    refute_nil words
    assert_includes body, "starts fresh"
    refute_includes body, "keeps its routine run row"
  end

  def test_a_one_flow_agent_page_tells_the_hand_off
    assert_includes events("architecture status"), "hands off"
  end

  def test_a_hand_off_without_an_offer_says_it_prints_no_next_line
    assert_includes subsection("intent end", "Agent::Intent::End"), "prints no next: line"
  end

  def test_a_step_whose_done_check_is_false_runs_on_every_call
    section = subsection("intent end", "Agent::Shared::WindDownIntent")

    assert_includes section, "Runs on every call; its done check is `false`."
    assert_includes text("intent end")[/## What one call reads.*?(?=\n## How a call ends)/m], "runs it again"
  end

  def test_a_hook_tells_the_steps_of_its_respond_and_omits_the_four_parts
    body = events("hook stop")

    ["Its steps run in this order:", "`return no_session unless session_id`", "`stop(event)`"].each { |part| assert_includes body, part }
    refute_includes body, "**Trigger**"
  end

  def test_a_command_with_no_workflow_tells_its_call_and_omits_the_four_parts
    body = events("status")

    assert_includes body, "![The call of plastic status](call.svg)"
    assert_includes body, "Its steps run in this order:"
    refute_includes body, "**Trigger**"
  end

  def test_every_routine_page_closes_the_events_with_the_four_parts
    Plastic::CLI::TABLE.each_key do |words|
      body = events(words)
      parts = ["**Trigger**", "**Activities**", "**Transitions**", "**Outcomes**"]

      if page(words).flows.empty?
        parts.each { |part| refute_includes body, part, words }
      else
        parts.each { |part| assert_includes body, part, words }
      end
    end

    assert_match(/\*\*Transitions\*\*.*`:intent`/, events("auto"))
  end

  def test_no_event_text_says_chain
    Plastic::CLI::TABLE.each_key { |words| refute_match(/chain/i, events(words).gsub(/^```.*?^```$/m, "").gsub(/`[^`]*`|\]\([^)]*\)/, ""), words) }
  end
end
