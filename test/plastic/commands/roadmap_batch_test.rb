# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/roadmap_batch"
require_relative "../../../scripts/lib/plastic/commands/roadmap_show"

class RoadmapBatchTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "batch", *args, table: Plastic::CLI::TABLE)

  def test_show_prints_the_goal_and_both_criteria
    call("r1", "1", "--title", "Wave one", "--goal", "Ship it", "--done", "a done", "--done", "b done")

    result = plastic("roadmap", "show", "r1", table: Plastic::CLI::TABLE)

    assert_includes result.out, "Ship it"
    assert_includes result.out, "a done"
    assert_includes result.out, "b done"
  end

  def test_a_second_call_on_the_same_batch_rewrites_it
    call("r1", "1", "--title", "First", "--goal", "G1", "--done", "a")
    call("r1", "1", "--title", "Second", "--goal", "G2", "--done", "b")

    rows = store_graphs.retrieval.batches("r1")

    assert_equal ["Second"], rows.map(&:title)
  end
end
