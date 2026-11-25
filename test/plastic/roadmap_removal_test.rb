# frozen_string_literal: true

require_relative "../test_helper"

# The roadmap is gone: needs links between intents replace it, so no command, page or schema table names it.
class RoadmapRemovalTest < Plastic::TestCase
  ROOT = File.expand_path("../..", __dir__)

  def test_the_roadmap_command_is_not_in_the_command_table
    refute Plastic::CLI::TABLE.keys.any? { |name| name.to_s.start_with?("roadmap") }, Plastic::CLI::TABLE.keys.grep(/roadmap/).inspect
  end

  def test_calling_plastic_roadmap_is_a_usage_error
    assert_equal 2, plastic("roadmap", "new", "plan", table: Plastic::CLI::TABLE).code
  end

  def test_no_command_page_of_the_reference_names_the_roadmap_command
    assert_empty Dir.glob(File.join(ROOT, "docs/reference/commands/roadmap*"))
  end

  def test_the_help_lists_no_roadmap_command
    refute_match(/roadmap/i, plastic("help", table: Plastic::CLI::TABLE).out)
  end

  def test_the_schema_declares_no_roadmap_table
    names = Plastic::Graph::Schema::TABLES.map { |table| table.name.to_s } if defined?(Plastic::Graph::Schema::TABLES)
    names ||= File.read(File.join(ROOT, "lib/plastic/graph/db/schema.rb")).scan(/create_table :(\w+)/).flatten

    assert_empty names & %w[roadmaps batches roadmap_items roadmap_edges roadmap_log]
  end

  def test_the_graph_writer_has_no_roadmap_method
    refute_predicate Plastic::Graph::GraphWriter.public_instance_methods.grep(/roadmap/), :any?
  end
end
