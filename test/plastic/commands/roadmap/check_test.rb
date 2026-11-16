# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/roadmap/batch"
require_relative "../../../../lib/plastic/commands/roadmap/add"
require_relative "../../../../lib/plastic/commands/roadmap/check"

class RoadmapCheckCaseTest < Plastic::TestCase
  def test_checking_a_roadmap_that_does_not_exist_exits_1_and_names_it
    assert_case line("roadmap check shop"), code: 1, out: "", err: ["no roadmap shop"]
  end
end

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

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "no findings"
    assert_includes result.out, "next: plastic roadmap show r1"
  end

  def test_a_roadmap_with_a_batch_and_no_items_exits_0_and_offers_the_show
    plastic("roadmap", "new", "r2", table: Plastic::CLI::TABLE)
    plastic("roadmap", "batch", "r2", "1", "--title", "T", "--goal", "G", table: Plastic::CLI::TABLE)

    result = call("r2")

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "no findings"
    assert_includes result.out, "next: plastic roadmap show r2"
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
