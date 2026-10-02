# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/roadmap_batch"
require_relative "../../../scripts/lib/plastic/commands/roadmap_log"

class RoadmapLogTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "log", *args, env: { "PLASTIC_SESSION" => "sess-1" }, table: Plastic::CLI::TABLE)

  def setup
    super
    plastic("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d", table: Plastic::CLI::TABLE)
  end

  def test_the_line_carries_its_session
    call("r1", "a", "note")

    line = store_graphs.retrieval.roadmap_log("r1").last

    assert_equal "a note", line.text
    assert_equal "sess-1", line.session_id
  end
end
