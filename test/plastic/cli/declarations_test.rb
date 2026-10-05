# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_new"

class DeclarationsTest < Plastic::TestCase
  class Declared
    extend Plastic::CLI::Declarations
  end

  def tool(&) = Class.new(Declared, &)

  def test_a_node_subject_takes_the_intent_and_the_node
    node = tool { node_subject }

    assert_equal [%i[intent_id id], %w[ID NODE]], [node.subject, node.arguments.map(&:label)]
  end

  def test_the_usage_line_names_every_argument_and_option
    declared = tool do
      argument :id, label: "ID", text: "the intent"
      option :dir, switch: "--dir DIR", text: "where"
    end

    assert_equal "plastic show ID [--dir DIR]", declared.usage_line("show")
  end

  def test_a_repeatable_option_starts_from_an_empty_list
    declared = tool { option :tag, switch: "--tag TAG", text: "a tag", repeatable: true }

    assert_equal [], declared.options.first.default
  end

  def test_reads_and_writes_collect_the_named_graphs
    declared = tool do
      reads :work
      writes :knowledge
      writes :references
    end

    assert_equal [[:work], %i[knowledge references]], [declared.reads, declared.writes]
  end

  def test_an_unknown_graph_is_invalid
    error = assert_raises(Plastic::Invalid) { tool { reads :weather } }

    assert_includes error.message, "unknown graph weather"
  end

  def test_the_tool_name_is_the_words_the_table_gives_the_class
    assert_equal "intent new", Plastic::Commands::IntentNew.tool_name
  end

  def test_describe_carries_the_summary_from_the_table
    description = Plastic::Commands::IntentNew.describe

    assert_equal ["intent new", Plastic::CLI::TABLE.dig("intent new", 1)], [description.name, description.summary]
  end

  def test_declared_names_list_arguments_then_options
    declared = tool do
      argument :id, label: "ID", text: "the intent"
      option :dir, switch: "--dir DIR", text: "where"
    end

    assert_equal %i[id dir], declared.declared_names
  end
end
