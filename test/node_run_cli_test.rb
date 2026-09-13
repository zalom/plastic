# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require "time"
require "yaml"
require "json"

require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/node_input"
require_relative "../scripts/lib/node_worktree"
require_relative "../scripts/lib/node_return"
require_relative "../scripts/lib/ready_set"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/worktree"

# node-run (intent 340b, G7c, n6): the CLI that runs one node's whole Codex
# attempt and writes only a return file, never a ledger transition. Matrix
# rows 6.11-6.17, 6.20-6.22, 6.24-6.29 in nodes/n6.md (6.1-6.10, 6.18, 6.19,
# 6.23 live in codex_adapter_test.rb; 6.27 lives in install_sync_test.rb).
#
# Every row spawns the real CLI as a subprocess (Open3), the house pattern
# for scripts/node-transition and scripts/ready-set. Rows that need `codex`
# itself run it against a tiny stub placed first on PATH - never the real
# binary: no network, no API key, no live model call anywhere in this file.
class NodeRunCliTest < Minitest::Test
  INTENT_ID = "1"
  INTENT_SLUG = "demo"
  PROJECT_SLUG = "demo-proj"
  NODE_RUN = File.expand_path("../scripts/node-run", __dir__)

  def setup
    @home = Dir.mktmpdir("node-run-home")
    @store = File.join(@home, ".plastic", "projects", PROJECT_SLUG, "store")
    @dir = File.join(@store, "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md"),
               "---\nid: \"#{INTENT_ID}\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
    FileUtils.remove_entry(@repo) if @repo && Dir.exist?(@repo)
    FileUtils.remove_entry(@codex_stub_bin) if @codex_stub_bin && Dir.exist?(@codex_stub_bin)
  end

  # --- fixture helpers ---------------------------------------------------------

  def write_graph(graph_body, decisions: "- D1 pick approach", goal: "Ship it.")
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Demo

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

  def write_node(filename, node:, kind:, files: [], budget: 100_000, body: nil)
    body ||= "# #{node} - a node\n\n## #{node} failure-mode matrix\n#{MATRIX}\n## Steps\n1. do it\n\n" \
             "## Proven by\n(filled at close)\n"
    File.write(File.join(@dir, "nodes", filename), <<~MD)
      ---
      node: #{node}
      kind: #{kind}
      files: #{files.inspect}
      budget: #{budget}
      ---
      #{body}
    MD
  end

  def savepoint_path
    File.join(@dir, "savepoint.md")
  end

  def line(subject, state, fields = nil, ts: "2026-01-01T00:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def append_savepoint(text)
    File.open(savepoint_path, "a") { |io| io.write(text) }
  end

  def write_lock(owner:, delegates: [])
    File.write(File.join(@dir, "delivery.lock"),
               JSON.generate("type" => "delivery", "owner_session" => owner, "delegates" => delegates))
  end

  def git(*args, dir: @repo)
    out, err, status = Open3.capture3("git", "-C", dir, *args.map(&:to_s))
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  # A real throwaway git repo, registered in projects.yml under
  # PROJECT_SLUG, with the intent worktree already checked out on the
  # intent branch - the only honest way to let the real node-run CLI
  # resolve a worktree to run in (node_worktree_test.rb's own pattern).
  def setup_real_repo
    @repo = Dir.mktmpdir("nrc-repo")
    git("init", "-q", "-b", "alpha")
    git("config", "user.email", "nrc@example.com")
    git("config", "user.name", "NRC Test")
    git("config", "gc.auto", "0")
    File.write(File.join(@repo, "README.md"), "hi\n")
    git("add", "README.md")
    git("commit", "-q", "-m", "init")

    @intent_worktree = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}")
    @intent_branch = "plastic/#{INTENT_ID}--#{INTENT_SLUG}"
    FileUtils.mkdir_p(File.dirname(@intent_worktree))
    git("worktree", "add", @intent_worktree, "-b", @intent_branch)

    FileUtils.mkdir_p(File.join(@home, ".plastic"))
    File.write(File.join(@home, ".plastic", "projects.yml"),
               YAML.dump("projects" => { PROJECT_SLUG => { "path" => @repo } }))
  end

  def build_context
    RunnerCore::Context.new(
      intent_dir: @dir, intent_id: INTENT_ID, intent_slug: INTENT_SLUG,
      store: @store, plastic_home: File.join(@home, ".plastic"), session: nil,
      worktree: @intent_worktree, worktree_branch: @intent_branch,
      graph: { ok: true, edges: {}, nodes: {} }, errors: []
    )
  end

  def provision_node_worktree(node, kind: "work")
    NodeWorktree.provision(build_context, node: node, kind: kind)
  end

  # A ready node with a real running line and a real, hashed packet on disk
  # at `attempt` - the fixture every non-refusal row needs.
  def build_running_node(node: "n1", session: "sess-1", attempt: 1, expires: "2099-01-01T00:00:00Z")
    build = NodeInput.build(intent_dir: @dir, node: node, holder: session, expires: expires, model: "sonnet",
                              attempt: attempt, force: true)
    raise "packet build failed: #{build[:errors].inspect}" unless build[:ok]

    append_savepoint(line(node, "running", holder: session, expires: expires, input: build[:sha], model: "sonnet"))
    build
  end

  def run_cli(*args, env: {})
    full_env = { "CLAUDE_CODE_SESSION_ID" => nil }.merge(env)
    Open3.capture3(full_env, RbConfig.ruby, NODE_RUN, *args)
  end

  def codex_stub_bin
    @codex_stub_bin ||= begin
      dir = Dir.mktmpdir("codex-stub-bin")
      write_codex_stub(dir)
      dir
    end
  end

  # A stand-in `codex` binary (never the real one - row 6.28/D23): parses
  # just enough of its own argv (-C/--cd, -o/--output-last-message) to act
  # on them, reads and discards its stdin (proving the real script never
  # blocks waiting for one), and behaves per STUB_CODEX_MODE so one small
  # script drives every subprocess-failure row plus the end-to-end commit.
  def write_codex_stub(bin_dir)
    path = File.join(bin_dir, "codex")
    File.write(path, <<~'RUBY')
      #!/usr/bin/env ruby
      def opt(args, *names)
        i = args.index { |a| names.include?(a) }
        i && args[i + 1]
      end

      args = ARGV.dup
      out_path = opt(args, "-o", "--output-last-message")
      cdir = opt(args, "-C", "--cd")
      $stdin.read
      mode = ENV["STUB_CODEX_MODE"].to_s

      case mode
      when "sleep"
        marker = ENV["STUB_CODEX_CHILD_MARKER"]
        if marker && !marker.empty?
          child = Process.spawn("sleep 2 && echo done > #{marker}")
          Process.detach(child)
        end
        sleep 30
      when "exit_nonzero"
        exit 7
      when "no_yaml"
        puts "not yaml, just prose, no document markers at all"
        exit 0
      when "commit"
        Dir.chdir(cdir) do
          File.write("stub-work.txt", "hello from stub codex\n")
          system("git", "add", "stub-work.txt")
          system({ "GIT_AUTHOR_NAME" => "Stub", "GIT_AUTHOR_EMAIL" => "stub@example.com",
                   "GIT_COMMITTER_NAME" => "Stub", "GIT_COMMITTER_EMAIL" => "stub@example.com" },
                 "git", "commit", "-q", "-m", "stub work")
        end
        sha = `git -C #{cdir} rev-parse HEAD`.strip
        File.write(out_path, "node: n1\nstatus: done\ncommit: #{sha}\nsummary: stub committed\n") if out_path
      else
        File.write(out_path, "node: n1\nstatus: done\ncommit: deadbeef0000\nsummary: stub ok\n") if out_path
      end
    RUBY
    FileUtils.chmod(0o755, path)
    path
  end

  def stub_env(extra = {})
    { "PATH" => "#{codex_stub_bin}#{File::PATH_SEPARATOR}#{ENV['PATH']}" }.merge(extra)
  end

  # --- 6.11: the attempt number comes from NodeInput.compute_attempt_number --

  def test_packet_path_comes_from_compute_attempt_number
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")
    provision_node_worktree("n1")

    # A first attempt that already failed - one running line, one
    # failed_verification line - before the second, LIVE attempt this call
    # must actually resolve.
    build_running_node(node: "n1", session: "sess-1", attempt: 1, expires: "2020-01-01T00:00:00Z")
    append_savepoint(line("n1", "failed_verification", reason: "synthetic"))
    build_running_node(node: "n1", session: "sess-1", attempt: 2)

    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1", env: stub_env)

    assert status.success?, err
    assert_equal File.join(@dir, "packets", "n1--a2.return.yml"), out.strip
    refute File.exist?(File.join(@dir, "packets", "n1--a1.return.yml")),
      "attempt 1's packet must never be the one this call absorbs"
  end

  # --- 6.12: a resolved packet that does not hash to input= is refused --------

  def test_refuses_on_input_hash_mismatch
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")

    build = NodeInput.build(intent_dir: @dir, node: "n1", holder: "sess-1", expires: "2099-01-01T00:00:00Z",
                              model: "sonnet", attempt: 1, force: true)
    assert build[:ok], build[:errors].inspect

    append_savepoint(line("n1", "running", holder: "sess-1", expires: "2099-01-01T00:00:00Z",
                            input: "deadbeefdead", model: "sonnet"))

    before = File.read(savepoint_path)
    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1")

    refute status.success?
    assert_match(/does not hash/, err)
    assert_empty out
    assert_equal before, File.read(savepoint_path)
    refute File.exist?(File.join(@dir, "packets", "n1--a1.return.yml"))
  end

  # --- 6.13: no live running line at all is refused ----------------------------

  def test_refuses_node_with_no_running_line
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")

    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1")

    refute status.success?
    assert_match(/no live running line/, err)
    assert_empty out
  end

  # --- 6.14: the packet the running line names is missing from disk -----------

  def test_refuses_when_packet_missing
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")

    append_savepoint(line("n1", "running", holder: "sess-1", expires: "2099-01-01T00:00:00Z",
                            input: "abcdefabcdef", model: "sonnet"))

    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1")

    refute status.success?
    assert_match(/packet is missing/, err)
    assert_empty out
  end

  # --- 6.15: a running line held by another session is refused ----------------

  def test_refuses_another_holders_lease
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "my-session")

    build_running_node(node: "n1", session: "other-session")

    out, err, status = run_cli(@dir, "--node", "n1", "--session", "my-session")

    refute status.success?
    assert_match(/other-session/, err)
    assert_empty out
  end

  # --- 6.16: no ledger transition is ever written, refusal or success ---------

  def test_writes_no_transition_on_any_path
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")
    provision_node_worktree("n1")

    run_cli(@dir, "--node", "n1", "--session", "sess-1")
    refute File.exist?(savepoint_path), "a refusal must never write savepoint.md into existence"

    build_running_node(node: "n1", session: "sess-1")
    before_run = File.read(savepoint_path)
    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1", env: stub_env)
    assert status.success?, err
    after_run = File.read(savepoint_path)
    assert_equal before_run, after_run, "a completed run must never write its own transition"
  end

  # --- 6.17: the return path is per-attempt ------------------------------------

  def test_return_path_is_per_attempt
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")
    provision_node_worktree("n1")

    build_running_node(node: "n1", session: "sess-1", attempt: 1, expires: "2020-01-01T00:00:00Z")
    out1, err1, status1 = run_cli(@dir, "--node", "n1", "--session", "sess-1", env: stub_env)
    assert status1.success?, err1
    path1 = out1.strip
    assert_equal File.join(@dir, "packets", "n1--a1.return.yml"), path1
    content1 = File.read(path1)

    append_savepoint(line("n1", "failed_verification", reason: "synthetic"))
    build_running_node(node: "n1", session: "sess-1", attempt: 2)
    out2, err2, status2 = run_cli(@dir, "--node", "n1", "--session", "sess-1", env: stub_env)
    assert status2.success?, err2
    path2 = out2.strip
    assert_equal File.join(@dir, "packets", "n1--a2.return.yml"), path2

    refute_equal path1, path2
    assert File.exist?(path1), "attempt 1's return must survive attempt 2's run"
    assert_equal content1, File.read(path1)
  end

  # --- 6.20: no YAML document anywhere writes an unparsable return -------------

  def test_no_yaml_writes_unparsable_return
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")
    provision_node_worktree("n1")
    build_running_node(node: "n1", session: "sess-1")

    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1",
                                env: stub_env("STUB_CODEX_MODE" => "no_yaml"))

    assert status.success?, err
    content = File.read(out.strip)
    assert_match(/no parsable YAML document/, content)
    refute NodeReturn.parse(content).ok, "the absorb gate must read this as unparsable"
  end

  # --- 6.21: a nonzero exit writes an unparsable return ------------------------

  def test_nonzero_exit_writes_unparsable_return
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")
    provision_node_worktree("n1")
    build_running_node(node: "n1", session: "sess-1")

    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1",
                                env: stub_env("STUB_CODEX_MODE" => "exit_nonzero"))

    assert status.success?, err
    content = File.read(out.strip)
    assert_match(/exited 7/, content)
    refute NodeReturn.parse(content).ok
  end

  # --- 6.22: a timeout writes an unparsable return -----------------------------

  def test_timeout_writes_unparsable_return
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")
    provision_node_worktree("n1")
    build_running_node(node: "n1", session: "sess-1")

    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1", "--timeout-seconds", "1",
                                env: stub_env("STUB_CODEX_MODE" => "sleep"))

    assert status.success?, err
    content = File.read(out.strip)
    assert_match(/timed out/, content)
    refute NodeReturn.parse(content).ok
  end

  # --- 6.24: a timeout kills the whole process group, not just the top pid ----

  def test_timeout_kills_the_process_group
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")
    provision_node_worktree("n1")
    build_running_node(node: "n1", session: "sess-1")

    marker_dir = Dir.mktmpdir("marker")
    marker = File.join(marker_dir, "child-ran")
    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1", "--timeout-seconds", "1",
                                env: stub_env("STUB_CODEX_MODE" => "sleep", "STUB_CODEX_CHILD_MARKER" => marker))

    assert status.success?, err
    sleep 2
    refute File.exist?(marker),
      "a child the stub codex spawned must die with the group, not outlive a kill on the top pid alone"
  ensure
    FileUtils.remove_entry(marker_dir) if marker_dir && Dir.exist?(marker_dir)
  end

  # --- 6.25: the return path is printed on success -----------------------------

  def test_prints_return_path
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")
    provision_node_worktree("n1")
    build_running_node(node: "n1", session: "sess-1")

    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1", env: stub_env)

    assert status.success?, err
    assert_equal File.join(@dir, "packets", "n1--a1.return.yml"), out.strip
  end

  # --- 6.26: exit codes distinguish a refusal from a written return -----------

  def test_exit_codes_distinguish_refusal_from_return
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")

    _out, _err, refusal_status = run_cli(@dir, "--node", "n1", "--session", "sess-1")
    refute_equal 0, refusal_status.exitstatus

    setup_real_repo
    provision_node_worktree("n1")
    build_running_node(node: "n1", session: "sess-1")
    _out2, err2, success_status = run_cli(@dir, "--node", "n1", "--session", "sess-1", env: stub_env)
    assert_equal 0, success_status.exitstatus, err2
  end

  # --- 6.28: a real subprocess of node-run itself, against a stub codex -------

  def test_subprocess_runs_against_stub_codex
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")
    provision_node_worktree("n1")
    build_running_node(node: "n1", session: "sess-1")

    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1", env: stub_env)

    assert status.success?, err
    return_file = out.strip
    assert File.exist?(return_file)
    content = File.read(return_file)
    assert_match(/status: done/, content)
    assert_match(/commit: deadbeef0000/, content)
  end

  # --- 6.29: a work node can commit inside the resolved sandbox, end to end ---

  # Proves the git commit succeeds against the exact --add-dir CodexAdapter
  # resolves (codex_adapter_test.rb proves the argv itself; this proves the
  # git call against it actually works), via the stub codex - never a real
  # Codex API call. No network, no key, and no live model call anywhere in
  # this suite; a genuinely Codex-enforced sandbox denial is not assertable
  # here without one, so it is not asserted.
  def test_work_node_commits_inside_the_sandbox
    setup_real_repo
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_lock(owner: "sess-1")
    provisioned = provision_node_worktree("n1")
    build_running_node(node: "n1", session: "sess-1")

    out, err, status = run_cli(@dir, "--node", "n1", "--session", "sess-1",
                                env: stub_env("STUB_CODEX_MODE" => "commit"))

    assert status.success?, err
    content = File.read(out.strip)
    parsed = NodeReturn.parse(content)
    assert parsed.ok, content
    assert_equal "done", parsed.status

    node_worktree = provisioned[:path]
    assert File.exist?(File.join(node_worktree, "stub-work.txt")),
      "the stub codex must have actually committed inside the node worktree, not merely claimed to"
    committed_sha = git("rev-parse", "HEAD", dir: node_worktree).strip
    assert_equal committed_sha, parsed.commit
  end
end
