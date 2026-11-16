# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/roadmap/batch"
require_relative "../../../../lib/plastic/commands/roadmap/log"

class RoadmapLogCaseTest < Plastic::TestCase
  def test_a_log_line_prints_the_text_and_offers_the_roadmap
    shop_batch

    assert_case line('roadmap log shop "batch 1 planned"'), code: 0, out: ["log: batch 1 planned", "next: plastic roadmap show shop"]
  end

  def test_a_log_line_on_a_roadmap_that_does_not_exist_exits_1_and_names_it
    assert_case line('roadmap log shop "batch 1 planned"'), code: 1, out: "", err: ["no roadmap shop"]
  end
end

class RoadmapLogTest < Plastic::TestCase
  def call(*args) = plastic("roadmap", "log", *args, env: { "PLASTIC_SESSION" => "sess-1" }, table: Plastic::CLI::TABLE)

  def setup
    super
    plastic("roadmap", "new", "r1", table: Plastic::CLI::TABLE)
    plastic("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d", table: Plastic::CLI::TABLE)
  end

  def test_the_line_carries_its_session
    call("r1", "a", "note")

    line = store_graphs.retrieval.roadmap_log("r1").last

    assert_equal "a note", line.text
    assert_equal "sess-1", line.session_id
  end
end
