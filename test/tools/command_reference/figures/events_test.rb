# frozen_string_literal: true

require "rexml/document"
require_relative "../../../command_reference_helper"

class CommandReferenceEventsFigureTest < Minitest::Test
  include CommandReferenceHelper

  FOLDER = "docs/reference/commands"
  LABELS = ["Code Workflow", "Agent Workflow", "Command", "Hook"].freeze
  LABEL_CLASSES = ["tag tag-code", "tag tag-agent", "tag tag-muted"].freeze
  STOP_CLASSES = { "tag tag-failure" => "Stops with a failure", "tag tag-refusal" => "Stops for the owner", "tag tag-handoff" => "Hands off, run again", "tag tag-end" => "Ends" }.freeze

  def drawings(name) = CommandReferenceHelper.files.select { |path, _| path.match?(%r{\A#{FOLDER}/[^/]+/#{name}\.svg\z}) }

  def texts(svg) = REXML::Document.new(svg).get_elements("//text").map { |each| [each.attributes["class"], each.text.to_s] }

  def events_of(words) = texts(CommandReferenceHelper.files.fetch("#{FOLDER}/#{page(words).slug}/events.svg"))

  def test_the_box_rule_catches_a_workflow_path
    assert CommandReference::Figures::BoxRule.code?("Plastic::Workflows::Code")
  end

  def test_the_box_rule_catches_a_method_name_and_a_file_name
    assert CommandReference::Figures::BoxRule.code?("calls close_intent")
    assert CommandReference::Figures::BoxRule.code?("reads end.rb")
  end

  def test_the_box_rule_leaves_plain_words_alone
    refute CommandReference::Figures::BoxRule.code?("Merge the code on GitHub")
  end

  def test_no_box_of_a_built_drawing_holds_a_code_symbol
    drawings("(?:events|workflows)").each do |path, svg|
      texts(svg).each { |_css, words| refute CommandReference::Figures::BoxRule.code?(words), "#{path}: #{words}" }
    end
  end

  def test_every_label_is_code_workflow_agent_workflow_command_or_hook
    drawings("events").each do |path, svg|
      labels = texts(svg).filter_map { |css, words| words if LABEL_CLASSES.include?(css) }

      refute_empty labels, path
      assert_empty labels - LABELS, path
    end
  end

  def test_a_command_with_no_workflow_has_one_box_labeled_command
    command = CommandReferenceHelper.pages.values.find { |each| each.kind == :command && each.flows.empty? }

    assert_includes events_of(command.words).map(&:last), "Command"
  end

  def test_a_hook_has_one_box_labeled_hook
    hook = CommandReferenceHelper.pages.values.find { |each| each.kind == :hook }

    assert_includes events_of(hook.words).map(&:last), "Hook"
  end

  def test_every_stop_text_has_its_exit_code
    drawings("events").each do |path, svg|
      texts(svg).select { |css, _| STOP_CLASSES.key?(css) }.each { |_css, words| assert_match(/EXIT \d/, words, path) }
    end
  end

  def test_the_key_names_each_kind_of_stop_the_drawing_uses
    drawings("events").each do |path, svg|
      found = texts(svg)
      key = found.filter_map { |css, words| words if css == "k" }

      found.map(&:first).uniq.select { |css| STOP_CLASSES.key?(css) }.each { |css| assert_includes key, STOP_CLASSES.fetch(css), path }
    end
  end

  def starts_of(svg) = svg.scan(/<path d="M (\d+) (\d+) L [^"]*" class="wire-/)

  def test_no_two_connectors_of_an_events_drawing_leave_a_box_at_the_same_place
    drawings("events").each do |path, svg|
      starts = starts_of(svg)

      assert_equal starts.uniq.size, starts.size, path
    end
  end

  def test_the_key_entries_of_an_events_drawing_leave_room_for_each_label
    drawings("events").each do |path, svg|
      key = REXML::Document.new(svg).get_elements("//text").select { |each| each.attributes["class"] == "k" }
      key.each_cons(2) do |now, after|
        room = after.attributes["x"].to_i - 20 - now.attributes["x"].to_i

        assert_operator room, :>=, 6 * now.text.to_s.size, "#{path}: #{now.text}"
      end
    end
  end

  def test_the_events_of_node_add_hold_its_failure_stop_with_the_words_of_its_gate
    words = events_of("node add").map(&:last)

    assert_includes words, "STOPS, EXIT 1"
    assert_includes words.join(" ").downcase, "the intent is missing, done or abandoned"
  end

  def test_the_events_of_node_add_hold_its_step_and_its_ending_with_the_next_line
    words = events_of("node add").map(&:last)

    assert_includes words.join(" "), "Add the node"
    assert_includes words, "ENDS, EXIT 0"
    assert_includes words.join(" "), "next: plastic edge add <intent id> FROM TO"
  end

  def test_the_events_of_intent_end_number_every_box_and_hold_a_refusal_with_exit_three
    found = events_of("intent end")

    assert_includes found.map(&:last), "STOPS, EXIT 3"
    assert_includes found.map(&:last), "HANDS OFF, EXIT 1"
    assert_includes found.map(&:last), "1"
  end

  def workflow_texts(each) = texts(CommandReferenceHelper.files.fetch("#{FOLDER}/#{each.slug}/workflows.svg"))

  def several_flows = CommandReferenceHelper.pages.values.select { |each| each.flows.size > 1 }

  def listed(words) = CommandReference::EventList.new(page(words)).events

  def ways(words) = listed(words).filter_map(&:way)

  def test_each_way_after_a_branch_of_intent_end_starts_with_its_condition_in_the_order_of_the_delivery
    found = ways("intent end")

    assert_equal 3, found.size
    assert_match(/\AWhen the intent still needs records or a verdict/, found[0])
    assert_match(/\AWhen the merge of the work is not verified yet/, found[1])
    assert_match(/\AWhen the records, the verdict and the merge are in place/, found[2])
  end

  def test_the_condition_of_a_way_is_drawn_in_the_events_drawing
    words = events_of("intent end").map(&:last)

    ways("intent end").each { |way| assert_includes words.join(" "), way.split.first(8).join(" ") }
  end

  def test_no_arrow_leads_from_the_end_of_one_way_into_the_start_of_the_next
    starts = listed("intent end").select(&:way)

    assert_equal 3, starts.size
    assert(starts.none?(&:joined))
    assert(listed("intent end").drop(1).reject(&:way).all?(&:joined))
  end

  def test_the_solid_arrows_of_the_events_drawing_are_one_for_each_joined_event_after_the_first
    CommandReferenceHelper.pages.each_value do |each|
      svg = CommandReferenceHelper.files.fetch("#{FOLDER}/#{each.slug}/events.svg")

      assert_equal listed(each.words).drop(1).count(&:joined), svg.scan(/class="wire"/).size, each.words
    end
  end

  def test_the_ending_that_says_the_intent_is_done_hangs_on_the_read_that_finds_it
    holders = listed("intent end").select { |event| event.stops.any? { |stop| stop.text.include?("already done") } }

    assert_equal ["Read the intent."], holders.map(&:text)
  end

  def test_the_endings_that_no_call_can_reach_are_not_drawn_in_the_events_of_intent_end
    words = listed("intent end").flat_map { |event| event.stops.map(&:text) }

    ["The completion records are ready.", "The merge and the architecture map are recorded.", "Nothing the intent started is left running."].each do |text|
      refute_includes words, text
    end
  end

  def test_the_endings_that_no_call_can_reach_are_not_drawn_in_the_workflows_of_intent_end
    words = workflow_texts(page("intent end")).map(&:last).join(" ")

    ["completion records are ready", "architecture map are recorded", "left running"].each { |text| refute_includes words, text }
  end

  def test_the_ways_of_the_workflows_drawing_of_intent_end_come_in_the_order_of_the_delivery
    words = workflow_texts(page("intent end")).map(&:last)
    at = ["still needs records", "not verified yet", "in place"].map { |text| words.index { |line| line.include?(text) } }

    assert_equal at.sort, at
    assert(at.all?)
  end

  def test_every_workflow_of_a_page_is_drawn_once
    several_flows.each do |each|
      drawn = workflow_texts(each).count { |css, _| css.start_with?("tag tag-code", "tag tag-agent") }

      assert_equal each.flows.size, drawn, each.words
    end
  end

  def test_the_workflows_drawing_holds_a_gate_card_for_every_workflow_with_a_gate
    several_flows.each do |each|
      expected = each.flows.count { |flow| CommandReference::FlowStops.new(flow).gates.any? }
      found = workflow_texts(each).count { |_css, words| words.start_with?("A check fails", "The step belongs to the owner") }

      assert_equal expected, found, each.words
    end
  end

  def test_the_workflows_drawing_holds_every_ending_of_every_workflow
    several_flows.each do |each|
      expected = each.flows.sum { |flow| CommandReference::FlowStops.new(flow).closing.size }
      found = workflow_texts(each).count { |css, _| ["tag tag-end", "tag tag-handoff"].include?(css) }

      assert_equal expected, found, each.words
    end
  end

  def test_the_workflows_of_intent_end_hold_a_box_for_each_workflow_with_its_summary_and_its_branch_texts
    svg = CommandReferenceHelper.files.fetch("#{FOLDER}/intent-end/workflows.svg")
    words = texts(svg).map(&:last).join(" ")

    assert_equal page("intent end").flows.size, texts(svg).count { |css, _| css.start_with?("tag tag-code", "tag tag-agent") }
    assert_includes words, "Closes the intent and releases its lock."
    assert_includes words, "the merge of the work is not verified yet"
  end
end
