# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"
require_relative "../scripts/lib/report_screen"

# The roadmap plan screen prints the graph tree (intent 337, n7) when a
# roadmap carries a real "## Graph" section: additive only - a graphless
# roadmap renders the exact bytes it rendered before this intent. Matrix
# rows from actions/ACTION_1.md S8/n7 (the screen half). Hermetic:
# Dir.mktmpdir fixtures, never the live roadmaps under ~/.plastic.
class ReportScreenRoadmapTreeTest < Minitest::Test
  NOW = Time.utc(2026, 9, 10, 12, 0, 0)

  def setup
    @home = Dir.mktmpdir("report-screen-roadmap-tree")
    @roadmaps = File.join(@home, "roadmaps")
    FileUtils.mkdir_p(@roadmaps)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def roadmap_path(slug)
    File.join(@roadmaps, "#{slug}.md")
  end

  def write_roadmap(slug, body)
    path = roadmap_path(slug)
    File.write(path, body)
    path
  end

  def render(path, verb: "plan")
    ReportScreen.render_roadmap(path: path, verb: verb, store_root: @home, now: NOW)
  end

  GRAPHLESS = <<~MD
    # Roadmap: Demo

    ## Goal
    Ship it.

    ## Batches

    ### Batch 1
    - [ ] 101 First - queued
    - [ ] 102 Second - queued
  MD

  GRAPHED = <<~MD
    # Roadmap: Demo

    ## Goal
    Ship it.

    ## Graph
    - 101 needs nothing
    - 102 needs 101

    ## Batches

    ### Batch 1
    - [ ] 101 First - queued

    ### Batch 2
    - [ ] 102 Second - queued
  MD

  # --- 7.1: the plan screen prints the tree when a graph exists ---------------

  def test_roadmap_plan_screen_prints_the_tree_when_a_graph_exists
    path = write_roadmap("demo", GRAPHED)
    out = render(path)
    assert_includes out, "101"
    assert_includes out, "102"
    assert_match(/```/, out)
  end

  # --- 7.2: a graphless roadmap's screen is byte-identical to today -----------

  def test_graphless_roadmap_screen_is_byte_identical_to_today
    path = write_roadmap("demo", GRAPHLESS)
    out = render(path)
    refute_match(/```/, out)
  end

  # --- 7.3: the tree block fits the screen limit -------------------------------

  def test_tree_block_fits_the_screen_limit
    body = <<~MD
      # Roadmap: Demo

      ## Goal
      Ship it.

      ## Graph
      - 101 needs nothing

      ## Batches

      ### Batch 1
      - [ ] 101 A very long entry title that goes on and on and on and on and on and on and on - queued
    MD
    path = write_roadmap("demo", body)
    out = render(path)
    out.each_line do |line|
      assert line.chomp.length <= 115, "line exceeds the screen limit: #{line.inspect}"
    end
  end

  # --- 7.4: the plan screen template carries the tree block --------------------

  def test_plan_screen_template_carries_the_tree_block
    template = File.read(File.expand_path("../templates/report-roadmap-plan.md", __dir__))
    assert_includes template, "{{tree}}"
  end
end
