# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"

# scripts/ready-set (intent 336, n8): no computed field ships without a
# script that reads it (327 D18, C19). Prints the ready order, the batches,
# the critical paths, and the blockers for every unready node; emits JSON
# for a caller like G7; and is registered with the installer.
class ReadySetCliTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/ready-set", __dir__)
  REPO = File.expand_path("..", __dir__)

  def setup
    @dir = Dir.mktmpdir("ready-set-cli")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "#{File.basename(@dir)}.md"), "---\nid: \"1\"\nintent: t\n---\n\n## Intent\nb\n")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def write_graph(body)
    File.write(File.join(@dir, "graph.md"), body)
  end

  def write_node(id, kind: "work")
    File.write(File.join(@dir, "nodes", "#{id}.md"), <<~MD)
      ---
      node: #{id}
      kind: #{kind}
      files: []
      budget: 1000
      ---
      # #{id}

      ## Steps
      1. go

      ## Proven by
      (later)
    MD
  end

  def run_cli(*args)
    Open3.capture3(RbConfig.ruby, SCRIPT, *args)
  end

  def test_cli_prints_the_ready_set
    write_graph("## Graph\n- n1 needs nothing\n")
    write_node("n1")
    out, err, status = run_cli(@dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/n1/, out)
  end

  def test_cli_prints_batches_and_critical_paths
    write_graph("## Graph\n- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1")
    write_node("n2")
    out, err, status = run_cli(@dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/batch/i, out)
    assert_match(/critical path/i, out)
  end

  def test_cli_prints_blockers_for_every_unready_node
    write_graph("## Graph\n- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1")
    write_node("n2")
    out, err, status = run_cli(@dir)
    assert_equal 0, status.exitstatus, err
    assert_match(/n2/, out)
    assert_match(/n1/, out) # n2's blocker names its unmet need, n1
  end

  def test_cli_json_carries_ready_batches_paths_and_blockers
    write_graph("## Graph\n- n1 needs nothing\n- n2 needs n1\n")
    write_node("n1")
    write_node("n2")
    out, err, status = run_cli(@dir, "--json")
    assert_equal 0, status.exitstatus, err
    data = JSON.parse(out)
    assert_equal ["n1"], data["ready"]
    assert_equal [["n1"], ["n2"]], data["batches"]
    assert data["paths"].is_a?(Array)
    assert data["blockers"].key?("n2")
  end

  def test_cli_ranker_flag_changes_the_order
    write_graph("## Graph\n- n1 needs nothing\n- n2 needs nothing\n")
    write_node("n1")
    write_node("n2")
    out1, err1, status1 = run_cli(@dir, "--json", "--ranker", "finish-first")
    out2, err2, status2 = run_cli(@dir, "--json", "--ranker", "critical-path")
    assert_equal 0, status1.exitstatus, err1
    assert_equal 0, status2.exitstatus, err2
    data1 = JSON.parse(out1)
    data2 = JSON.parse(out2)
    assert_equal "finish-first", data1["ranker"]
    assert_equal "critical-path", data2["ranker"]
  end

  def test_cli_exits_two_on_a_non_intent_directory
    empty = Dir.mktmpdir("ready-set-cli-empty")
    out, _err, status = run_cli(empty)
    assert_equal 2, status.exitstatus, out
  ensure
    FileUtils.remove_entry(empty) if empty && Dir.exist?(empty)
  end

  def test_cli_exits_non_zero_on_a_cycle
    write_graph("## Graph\n- n1 needs n2\n- n2 needs n1\n")
    write_node("n1")
    write_node("n2")
    _out, _err, status = run_cli(@dir)
    refute_equal 0, status.exitstatus
  end

  def test_the_installed_manifest_carries_ready_set
    core_lib = File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))
    assert_includes core_lib, %("scripts/lib/ready_set.rb")
    assert_includes core_lib, %("scripts/ready-set")
  end

  def test_internals_doc_describes_the_graph_frontier
    doc = File.read(File.join(REPO, "docs", "internals.md"))
    refute_match(/RoadmapQueue.{0,40}own private .frontier_for., unchanged/, doc)
  end
end
