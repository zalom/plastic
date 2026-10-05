# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/log_roadmap"

class LogRoadmapTest < Plastic::TestCase
  include RoadmapHelper

  def log(slug = "r1")
    run_workflow(Plastic::Workflows::LogRoadmap, graphs: Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1"),
      slug:, text: "batch 1 started")
  end

  def test_the_line_is_written_with_the_session_and_printed
    roadmap

    outcome, context = log

    assert_equal [:done, ["log: batch 1 started"]], [outcome, context.printed]
    assert_equal "s-1", sole(retrieval.roadmap_log("r1")).session_id
  end

  def test_an_unknown_roadmap_fails_with_no_line
    outcome, = log("r9")

    assert_equal "code_log_roadmap, gate: no roadmap r9", outcome.message
    assert_empty retrieval.roadmap_log("r9")
  end
end
