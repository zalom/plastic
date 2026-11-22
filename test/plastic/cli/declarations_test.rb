# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/intent/new"
require_relative "../../../lib/plastic/commands/search"
require_relative "../../../lib/plastic/commands/document/get"
require_relative "../../../lib/plastic/commands/document/batch"
require_relative "../../../lib/plastic/commands/intent/discover"
require_relative "../../../lib/plastic/commands/intent/context"
require_relative "../../../lib/plastic/commands/project/load"

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
      writes :retrieval
    end

    assert_equal [[:work], %i[knowledge retrieval]], [declared.reads, declared.writes]
  end

  def test_an_unknown_graph_is_invalid
    error = assert_raises(Plastic::Invalid) { tool { reads :weather } }

    assert_includes error.message, "unknown graph weather"
  end

  def test_opens_no_store_marks_a_command_that_opens_no_store
    assert_equal [true, false], [tool { opens_no_store }.opens_no_store?, tool {}.opens_no_store?]
  end

  def test_no_source_names_the_old_graphless_declaration
    sources = Dir[File.join(__dir__, "../../../scripts/**/*.rb")]

    refute_empty sources
    assert_empty sources.select { |path| File.read(path).include?("graphless") }
  end

  def test_the_tool_name_is_the_words_the_table_gives_the_class
    assert_equal "intent new", Plastic::Commands::Intent::New.tool_name
  end

  def test_declared_names_list_arguments_then_options
    declared = tool do
      argument :id, label: "ID", text: "the intent"
      option :dir, switch: "--dir DIR", text: "where"
    end

    assert_equal %i[id dir], declared.declared_names
  end

  def test_changes_names_each_place_with_its_words
    declared = tool { changes(local: "The lock is released", work: "The intent is closed") }

    assert_equal({ local: "The lock is released", work: "The intent is closed" }, declared.changes)
  end

  def test_changes_with_an_empty_hash_declares_that_the_command_changes_nothing
    assert_equal({}, tool { changes({}) }.changes)
  end

  def test_a_command_that_declares_no_changes_answers_nil
    assert_nil tool {}.changes
  end

  def test_the_config_command_declares_the_setting_it_writes
    require_relative "../../../lib/plastic/commands/config"

    assert_equal [:home], Plastic::Commands::Config.changes.keys
  end
end

class RetrievalReadsDeclarationTest < Minitest::Test
  READERS = %w[Search Document::Get Document::Batch Intent::Discover Intent::Context Project::Load].freeze

  def test_every_command_that_reads_the_retrieval_database_declares_it
    READERS.each do |name|
      klass = Plastic::Commands.const_get(name)

      assert_includes klass.reads, :retrieval, "#{name} reads retrieval_graph.db and declares reads :retrieval"
    end
  end
end
