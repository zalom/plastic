# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

# RunnerWatchCliTest (intent 340a, G7b, n2): the two rows that only a real
# subprocess can prove - row 2.4 (the bug 340 shipped for `sweep`: a verb
# wired in-process but missing its CLI arm) and row 2.6 (Claude Code's
# unattended-start refusal, which must exit before RunnerWatch.tick ever
# takes the tick lock or writes anything). Hermetic like runner_cli_test.rb:
# every fixture lives under Dir.mktmpdir, no real ~/.plastic is ever
# touched, and `scripts/runner watch` here spawns the real script through
# Open3, never RunnerWatch in-process.
class RunnerWatchCliTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/runner", __dir__)

  MATRIX = <<~MD
    | Operation | Failure mode | Test |
    | --- | --- | --- |
    | op | mode | a test |
  MD

  def setup
    @home = Dir.mktmpdir("runner-watch-cli-340a")
    @store = File.join(@home, ".plastic", "store")
    @dir = File.join(@store, "1--demo")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "1--demo.md"), "---\nid: \"1\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_graph(graph_body)
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      #{graph_body}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  def write_node(node, kind: "work")
    File.write(File.join(@dir, "nodes", "#{node}.md"), <<~MD)
      ---
      node: #{node}
      kind: #{kind}
      files: []
      budget: 100000
      ---
      # #{node} - a node

      ## #{node} failure-mode matrix
      #{MATRIX}
      ## Steps
      1. do it

      ## Proven by
      (filled at close)
    MD
  end

  def record_path
    File.join(@dir, "watch.record")
  end

  def state_path
    File.join(@dir, "watch.state")
  end

  def run_cli(*args, env: {})
    full_env = { "CLAUDE_CODE_SESSION_ID" => nil }.merge(env)
    Open3.capture3(full_env, RbConfig.ruby, SCRIPT, *args)
  end

  # --- 2.4: the CLI arm actually exists, not only the internal module ------------

  def test_subprocess_watch_prints_the_class
    write_graph("- n1 needs nothing\n")
    write_node("n1")

    out, err, status = run_cli("watch", @dir)

    assert_equal 0, status.exitstatus, out + err
    assert_match(/^class: /, out)
  end

  # --- 2.6: --dispatch on Claude Code is refused before any write -----------------

  def test_dispatch_refused_on_claude_code_names_q6
    write_graph("- n1 needs nothing\n")
    write_node("n1")

    out, err, status = run_cli("watch", @dir, "--dispatch")

    assert_equal 1, status.exitstatus, out + err
    assert_includes err, "Unattended start is delivered only where a Ruby loop owns dispatch"
    assert_includes err, "327 Q6"
    refute File.exist?(record_path), "a refused --dispatch must leave no watch.record line behind"
    refute File.exist?(state_path), "a refused --dispatch must write no watch.state either"
  end
end
