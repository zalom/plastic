# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../test_helpers/resources_homes"
require_relative "../../../../../lib/plastic/commands/intent/repair"
require_relative "../../../../../lib/plastic/graph/knowledge/resources/sort_plan"

# A node's schema lives at resources/tmp/schemas/NODE.json, where the resources layout already keeps scratch files.
class SchemaLayoutTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  SCHEMA = "#{INTENT}/resources/tmp/schemas/n1.json"

  def setup
    super
    write(SCHEMA, "{\"type\":\"object\"}\n")
  end

  def moves = Plastic::Graph::Knowledge::Resources::SortPlan.new(store_folder).moves

  def store_folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

  def repair = plastic("intent", "repair", "--all", "--project", "global", table: Plastic::CLI::TABLE)

  def test_the_sort_plan_moves_nothing_for_the_schema_file
    assert_empty moves.map(&:to_s).grep(/schemas/)
  end

  def test_a_store_with_a_schema_file_is_sorted_for_the_doctor
    assert_equal [], moves
  end

  def test_a_repair_leaves_the_schema_file_where_it_is_with_its_bytes
    repair

    assert_equal "{\"type\":\"object\"}\n", File.read(store_path(SCHEMA))
  end
end
