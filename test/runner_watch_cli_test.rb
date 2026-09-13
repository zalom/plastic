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

  # --- 3.2: --install-timer writes the delivery-watch plist and prints the load line ---

  def test_install_timer_writes_a_delivery_watch_plist
    write_graph("- n1 needs nothing\n")
    write_node("n1")
    home = Dir.mktmpdir("runner-watch-cli-home")

    begin
      out, err, status = run_cli("watch", @dir, "--install-timer", "--home", home)

      assert_equal 0, status.exitstatus, out + err
      plist_path = File.join(home, "Library", "LaunchAgents", "com.plastic.delivery-watch.1.plist")
      assert File.file?(plist_path), "--install-timer must write the delivery-watch plist under --home"
      assert_includes out, plist_path
      assert_includes out, "launchctl load #{plist_path}"
      refute File.exist?(record_path), "--install-timer must never take a tick"
      refute File.exist?(state_path)
    ensure
      FileUtils.remove_entry(home)
    end
  end

  # --- 3.3: --dispatch --harness codex ride only where unattended start holds -----

  def test_install_timer_dispatches_only_where_unattended_start_holds
    write_graph("- n1 needs nothing\n")
    write_node("n1")
    home = Dir.mktmpdir("runner-watch-cli-home")
    plist_path = File.join(home, "Library", "LaunchAgents", "com.plastic.delivery-watch.1.plist")

    begin
      out, err, status = run_cli("watch", @dir, "--install-timer", "--home", home)
      assert_equal 0, status.exitstatus, out + err
      claude_code_content = File.read(plist_path)
      refute_includes claude_code_content, "--dispatch",
                       "a Claude Code machine must never claim unattended start (327 Q6)"

      out2, err2, status2 = run_cli("watch", @dir, "--install-timer", "--home", home, "--harness", "codex")
      assert_equal 0, status2.exitstatus, out2 + err2
      codex_content = File.read(plist_path)
      assert_includes codex_content, "<string>--dispatch</string>"
      assert_includes codex_content, "<string>--harness</string>"
      assert_includes codex_content, "<string>codex</string>"
    ensure
      FileUtils.remove_entry(home)
    end
  end

  # --- 3.4: the label carries the intent id ----------------------------------------

  def test_install_timer_label_is_per_intent
    write_graph("- n1 needs nothing\n")
    write_node("n1")
    other_dir = File.join(@store, "2--demo-two")
    FileUtils.mkdir_p(File.join(other_dir, "nodes"))
    File.write(File.join(other_dir, "2--demo-two.md"), "---\nid: \"2\"\nintent: t\n---\n\n## Intent\nbody\n")
    FileUtils.cp(File.join(@dir, "graph.md"), File.join(other_dir, "graph.md"))
    FileUtils.cp(File.join(@dir, "nodes", "n1.md"), File.join(other_dir, "nodes", "n1.md"))
    home = Dir.mktmpdir("runner-watch-cli-home")

    begin
      out1, err1, status1 = run_cli("watch", @dir, "--install-timer", "--home", home)
      assert_equal 0, status1.exitstatus, out1 + err1
      out2, err2, status2 = run_cli("watch", other_dir, "--install-timer", "--home", home)
      assert_equal 0, status2.exitstatus, out2 + err2

      first = File.join(home, "Library", "LaunchAgents", "com.plastic.delivery-watch.1.plist")
      second = File.join(home, "Library", "LaunchAgents", "com.plastic.delivery-watch.2.plist")
      assert File.file?(first), "the first intent's own timer must survive the second intent's install"
      assert File.file?(second), "a second intent must get its own plist, never overwrite the first"
      refute_equal File.read(first), File.read(second)
    ensure
      FileUtils.remove_entry(home)
    end
  end
end
