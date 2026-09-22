# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "time"

require_relative "../scripts/lib/runner_rewind"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/node_file"
require_relative "../scripts/lib/graph_file"
require_relative "../scripts/lib/ready_set"
require_relative "../scripts/lib/worktree"

# RunnerRewind (intent 340, G7, n6): resets the intent branch to a node's
# own recorded commit, supersedes every downstream node, and respins the
# rewound node itself. Matrix rows 6.16-6.21 in nodes/n6.md.
class RunnerRewindTest < Minitest::Test
  INTENT_ID = "340"
  INTENT_SLUG = "rewind-fixture"

  # A runner double that raises if ever called, standing in for "no git call
  # is made before confirm is checked" (matrix row 6.16).
  class RefusingToRunRunner
    def run(*)
      raise "a git call must never happen before --confirm is checked"
    end
  end

  def setup
    @home = Dir.mktmpdir("rewind-home")
    @dir = File.join(@home, "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md"),
               "---\nid: \"#{INTENT_ID}\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
    FileUtils.remove_entry(@repo) if @repo && Dir.exist?(@repo)
  end

  # --- fixture helpers -----------------------------------------------------------

  def write_graph(graph_body, decisions: "- D1 pick an approach", goal: "Ship it.")
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Fixture

      ## Goal
      #{goal}

      ## Decisions
      #{decisions}

      ## Graph
      #{graph_body}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  MATRIX = <<~MD
    | Operation | Failure mode | Test |
    | --- | --- | --- |
    | op | mode | a test |
  MD

  def write_work_node(node, files: ["scripts/lib/foo.rb"], budget: 100_000)
    File.write(File.join(@dir, "nodes", "#{node}.md"), <<~MD)
      ---
      node: #{node}
      kind: work
      files: #{files.inspect}
      budget: #{budget}
      ---
      # #{node} - a work node

      ## #{node} failure-mode matrix
      #{MATRIX}
      ## Steps
      1. do it

      ## Proven by
      (filled at close)
    MD
  end

  def write_decision_node(node)
    File.write(File.join(@dir, "nodes", "#{node}.md"), <<~MD)
      ---
      node: #{node}
      kind: decision
      files: []
      budget: 20000
      ---
      # #{node} - a decision to make

      ## Question
      Which approach should this take?
    MD
  end

  def write_savepoint(content)
    File.write(File.join(@dir, "savepoint.md"), content)
  end

  def line(subject, state, fields = nil, ts: "2026-01-01T00:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def savepoint_path
    File.join(@dir, "savepoint.md")
  end

  def savepoint_content
    File.exist?(savepoint_path) ? File.read(savepoint_path) : ""
  end

  def graph_path
    File.join(@dir, "graph.md")
  end

  def build_context(worktree: nil)
    loaded = ReadySet.load_graph(@dir)
    RunnerCore::Context.new(
      intent_dir: @dir, intent_id: INTENT_ID, intent_slug: INTENT_SLUG,
      store: nil, plastic_home: @home, session: nil,
      worktree: worktree, worktree_branch: nil,
      graph: loaded.merge(ok: true), errors: []
    )
  end

  def git(*args, dir: @repo)
    out, err, status = Open3.capture3("git", "-C", dir, *args.map(&:to_s))
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  # A real throwaway git repo with the intent worktree checked out on the
  # intent branch (runner_dispatch_test.rb's own pattern) - the only honest
  # way to test a real `git reset --hard`.
  def setup_real_repo
    @repo = Dir.mktmpdir("rewind-repo")
    git("init", "-q", "-b", "alpha")
    git("config", "user.email", "rw@example.com")
    git("config", "user.name", "RW Test")
    git("config", "gc.auto", "0")
    File.write(File.join(@repo, "README.md"), "hi\n")
    git("add", "README.md")
    git("commit", "-q", "-m", "init")

    @intent_worktree = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.dirname(@intent_worktree))
    git("worktree", "add", @intent_worktree, "-b", "plastic/#{INTENT_ID}--#{INTENT_SLUG}")
  end

  def commit_in_intent_worktree(message)
    File.write(File.join(@intent_worktree, "#{message.gsub(/\s+/, '-')}.txt"), "#{message}\n")
    git("-C", @intent_worktree, "add", ".")
    git("-C", @intent_worktree, "commit", "-q", "-m", message)
    git("-C", @intent_worktree, "rev-parse", "HEAD").strip
  end

  # --- 6.16: refuse rewind without --confirm -----------------------------------

  def test_rewind_requires_confirm
    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(line("n1", "done", gates: "g", commit: "deadbeef"))

    result = RunnerRewind.rewind(build_context, node: "n1", confirm: false, runner: RefusingToRunRunner.new)

    refute result[:ok]
    assert_equal "confirm_required", result[:reason]
  end

  # --- 6.17: reset the intent branch to the node's recorded commit -------------

  def test_rewind_resets_to_node_commit
    setup_real_repo
    n1_commit = commit_in_intent_worktree("n1 work")
    commit_in_intent_worktree("n4 work, built on n1")

    write_graph("- n1 needs nothing\n- n4 needs n1\n")
    write_work_node("n1")
    write_work_node("n4")
    write_savepoint(line("n1", "done", gates: "g", commit: n1_commit) +
                     line("n4", "done", gates: "g", commit: "whatever"))

    result = RunnerRewind.rewind(build_context(worktree: @intent_worktree), node: "n1", confirm: true)

    assert result[:ok], result.inspect
    assert_equal n1_commit, result[:reset_to]
    assert_equal n1_commit, git("rev-parse", "HEAD", dir: @intent_worktree).strip
  end

  # --- 6.18: every downstream node is marked superseded -------------------------

  def test_rewind_supersedes_downstream_nodes
    setup_real_repo
    n1_commit = commit_in_intent_worktree("n1 work")

    write_graph("- n1 needs nothing\n- n4 needs n1\n- n7 needs n4\n")
    write_work_node("n1")
    write_work_node("n4")
    write_work_node("n7")
    write_savepoint(line("n1", "done", gates: "g", commit: n1_commit) +
                     line("n4", "done", gates: "g", commit: "c4") +
                     line("n7", "done", gates: "g", commit: "c7"))

    result = RunnerRewind.rewind(build_context(worktree: @intent_worktree), node: "n1", confirm: true)

    assert result[:ok], result.inspect
    assert_equal %w[n4 n7], result[:superseded].sort
    assert_equal "superseded", NodeLedger.status_for_content(savepoint_content, "n4")
    assert_equal "superseded", NodeLedger.status_for_content(savepoint_content, "n7")
  end

  # --- 6.19: the rewound node is respun, never written as planned --------------

  def test_rewind_respins_instead_of_planning
    setup_real_repo
    n1_commit = commit_in_intent_worktree("n1 work")

    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(line("n1", "done", gates: "g", commit: n1_commit))

    result = RunnerRewind.rewind(build_context(worktree: @intent_worktree), node: "n1", confirm: true)

    assert result[:ok], result.inspect
    refute_nil result[:respun_to]
    assert_equal "superseded", NodeLedger.status_for_content(savepoint_content, "n1")
    refute_equal "planned", NodeLedger.status_for_content(savepoint_content, "n1")
    assert File.exist?(File.join(@dir, "nodes", "#{result[:respun_to]}.md"))
  end

  # --- 6.19a: the successor starts with clean cap counters ----------------------

  def test_respun_node_starts_with_clean_counters
    setup_real_repo
    n1_commit = commit_in_intent_worktree("n1 work")

    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(
      line("n1", "failed_verification", gates: "g", reason: "suite_red") +
      line("n1", "failed_verification", gates: "g", reason: "suite_red") +
      line("n1", "done", gates: "g", commit: n1_commit)
    )

    result = RunnerRewind.rewind(build_context(worktree: @intent_worktree), node: "n1", confirm: true)
    succ = result[:respun_to]

    entries = NodeLedger.entries_from_content(savepoint_content)
    assert_equal 0, ReadySet.attempts_count(entries, succ)
    assert_equal 0, ReadySet.failed_verification_count(entries, succ)
    assert_equal 2, ReadySet.failed_verification_count(entries, "n1"),
      "n1's own historical failed_verification count must never be erased"
  end

  # --- 6.20: refuse rewind on a node with no recorded commit --------------------

  def test_rewind_refuses_node_without_commit
    write_graph("- d1 needs nothing\n")
    write_decision_node("d1")
    write_savepoint(line("d1", "done", gates: "answer", verdict: "answered"))

    result = RunnerRewind.rewind(build_context, node: "d1", confirm: true, runner: RefusingToRunRunner.new)

    refute result[:ok]
    assert_equal "no_recorded_commit", result[:reason]
  end

  # --- 6.21: refuse rewind while any node is running -----------------------------

  def test_rewind_refuses_while_a_node_runs
    write_graph("- n1 needs nothing\n- n2 needs nothing\n")
    write_work_node("n1")
    write_work_node("n2")
    write_savepoint(
      line("n1", "done", gates: "g", commit: "c1") +
      line("n2", "running", holder: "h", expires: "2026-01-01T01:00:00Z", input: "p", model: "sonnet")
    )

    result = RunnerRewind.rewind(build_context, node: "n1", confirm: true, runner: RefusingToRunRunner.new)

    refute result[:ok]
    assert_equal "a_node_is_running", result[:reason]
  end
end
