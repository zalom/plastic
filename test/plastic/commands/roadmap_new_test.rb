# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/roadmap_new"

class RoadmapNewTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "new", *args, table: Plastic::CLI::TABLE)

  def test_new_creates_the_roadmap_row_and_offers_the_first_batch
    result = call("r1", "--title", "Make it useful", "--goal", "Close the blockers")

    assert_equal [0, "Make it useful", "Close the blockers"], [result.code, *store_graphs.retrieval.roadmap("r1").to_h.values_at(:title, :goal)]
    assert_includes result.out, "next: plastic roadmap batch r1 1 --project global"
  end

  def test_a_roadmap_with_no_title_is_titled_by_its_name
    call("r1")

    assert_equal "r1", store_graphs.retrieval.roadmap("r1").title
  end

  def test_new_prints_the_roadmap_file
    call("r1")

    assert_path_exists store_path("roadmaps/r1.md")
  end

  def test_new_on_an_existing_roadmap_exits_1_and_changes_nothing
    call("r1", "--title", "First")

    result = call("r1", "--title", "Second")

    assert_equal [1, "First"], [result.code, store_graphs.retrieval.roadmap("r1").title]
    assert_includes result.err, "roadmap r1 already exists"
  end

  def test_the_name_must_be_given
    assert_equal 2, call.code
  end
end
