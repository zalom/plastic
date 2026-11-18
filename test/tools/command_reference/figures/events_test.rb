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

  BOX_CODE = %r{::|\b[a-z]+_[a-z_]+\b|\.rb\b|\(\)}

  def code?(words) = words.to_s.match?(BOX_CODE)

  def test_the_box_rule_catches_a_workflow_path
    assert code?("Plastic::Workflows::Code")
  end

  def test_the_box_rule_catches_a_method_name_and_a_file_name
    assert code?("calls close_intent")
    assert code?("reads end.rb")
  end

  def test_the_box_rule_leaves_plain_words_alone
    refute code?("Merge the code on GitHub")
  end

  def test_no_box_of_a_built_drawing_holds_a_code_symbol
    drawings("(?:events|workflows)").each do |path, svg|
      texts(svg).each { |_css, words| refute code?(words), "#{path}: #{words}" }
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
end
