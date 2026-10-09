# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/roadmap_batch"
require_relative "../../../scripts/lib/plastic/commands/roadmap_add"
require_relative "../../../scripts/lib/plastic/commands/roadmap_check"

class RoadmapCheckTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "check", *args, table: Plastic::CLI::TABLE)

  def setup
    super
    plastic("roadmap", "new", "r1", table: Plastic::CLI::TABLE)
    plastic("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d", table: Plastic::CLI::TABLE)
    plastic("roadmap", "add", "r1", "1", "a", "--title", "A", table: Plastic::CLI::TABLE)
  end

  def test_a_clean_roadmap_exits_0
    result = call("r1")

    assert_equal 0, result.code
  end

  def test_a_dangling_edge_exits_1_naming_it
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.put(:roadmap_edges, { roadmap: "r1", from: "ghost", to: "a", kind: "after" }, statement: :insert)
    end

    result = call("r1")

    assert_equal 1, result.code
    assert_includes result.out, "ghost"
  end
end
