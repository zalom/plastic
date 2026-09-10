# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

# scripts/roadmap-graph (intent 337, n4): the CLI over n1/n3/RoadmapMigration
# - `check`, `render`, `migrate`, every verb honouring --dry-run. Matrix rows
# from actions/ACTION_1.md S6/n4 (the roadmap_graph_cli_test.rb half).
# Hermetic: shells out to the real script (Open3), every fixture lives in a
# Dir.mktmpdir.
class RoadmapGraphCliTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  CLI = File.join(REPO, "scripts", "roadmap-graph")

  def setup
    @dir = Dir.mktmpdir("roadmap-graph-cli")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def roadmap_path
    File.join(@dir, "demo.md")
  end

  def write_roadmap(body)
    File.write(roadmap_path, body)
  end

  def basic(batches_body, graph_body)
    <<~MD
      # Roadmap: Demo

      ## Goal
      Ship it.

      ## Graph
      #{graph_body}
      ## Batches
      #{batches_body}
    MD
  end

  def run_cli(*args)
    Open3.capture3("ruby", CLI, *args)
  end

  # --- 4.9: check on a cyclic roadmap exits 1 with the path --------------------

  def test_check_on_a_cyclic_roadmap_exits_1_with_the_path
    write_roadmap(basic(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
      - [ ] 102 Second - queued
    B
      - 101 needs 102
      - 102 needs 101
    G
    out, _err, status = run_cli("check", roadmap_path)
    assert_equal 1, status.exitstatus
    assert_match(/101.*>.*102.*>.*101/, out)
  end

  # --- 4.10: --dry-run writes nothing and prints the diff ----------------------

  def test_dry_run_writes_nothing_and_prints_the_diff
    write_roadmap(basic(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs nothing
    G
    before = File.read(roadmap_path)
    out, _err, status = run_cli("render", roadmap_path, "--dry-run")
    assert_equal 0, status.exitstatus
    assert_equal before, File.read(roadmap_path)
    assert_includes out, "## Tree"
  end

  # --- 4.11: an unknown or missing path exits with a named reason -------------

  def test_unknown_path_exits_with_a_named_reason_not_a_backtrace
    out, err, status = run_cli("check", File.join(@dir, "nope.md"))
    refute_equal 0, status.exitstatus
    refute_match(/\.rb:\d+:in/, out + err)
  end

  # --- 4.12: no argument exits 2, unknown verb exits 2 -------------------------

  def test_no_argument_exits_2_and_unknown_verb_exits_2
    _out, _err, status = run_cli
    assert_equal 2, status.exitstatus

    _out2, _err2, status2 = run_cli("frobnicate", roadmap_path)
    assert_equal 2, status2.exitstatus
  end

  # --- 4.13: check exits non-zero when the graph names an unlisted id ---------

  def test_check_exits_1_when_the_graph_names_an_unlisted_id
    write_roadmap(basic(<<~B, <<~G))
      ### Batch 1
      - [ ] 101 First - queued
    B
      - 101 needs 999
      - 999 needs nothing
    G
    out, _err, status = run_cli("check", roadmap_path)
    assert_equal 1, status.exitstatus
    assert_match(/999/, out)
  end

  # --- 4.14: the new scripts and libs are registered in CORE_FILES ------------

  def test_new_scripts_and_libs_are_registered_in_core_files
    source = File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))
    %w[scripts/roadmap-graph scripts/lib/roadmap_migration.rb].each do |path|
      assert_includes source, path.inspect, "#{path} must be registered in CORE_FILES"
    end
  end
end
