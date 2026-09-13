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

# scripts/runner has no .rb extension, so `require_relative` cannot resolve
# it; `load` has no such restriction and is idempotent here since Runner is
# a module, reopened harmlessly on a second load. Loaded only so this file
# can read Runner::DOCUMENT_BOUNDARY - every other call into the CLI goes
# through a real subprocess, never through this loaded copy.
load File.expand_path("../scripts/runner", __dir__)

# HarnessAdapterDogfoodTest (intent 340b, G7c, n5): the one file in this
# intent that drives the Claude Code adapter as a user actually drives it.
# 340 shipped a green suite over a `runner step` that raised on every real
# call, because every test drove the module API directly and none turned
# the key through the CLI. This file turns the key: an authored scratch
# intent, a real git repository, a real lock, a real node worktree, walked
# end to end by subprocess calls only (`runner status`, then `runner
# step`), with the rendered Claude block read back out of stdout and
# checked against what the harness would actually need to spawn.
#
# Matrix rows 5.1-5.13 in nodes/n5.md (5.14 is a process rule the return's
# own findings list satisfies, not a unit test).
class HarnessAdapterDogfoodTest < Minitest::Test
  INTENT_ID = "1"
  INTENT_SLUG = "demo"
  PROJECT_SLUG = "demo-proj"
  SCRIPT = File.expand_path("../scripts/runner", __dir__)
  AGENTS_DIR = File.expand_path("../agents", __dir__)

  def setup
    @home = Dir.mktmpdir("dogfood-home")
    @store = File.join(@home, ".plastic", "projects", PROJECT_SLUG, "store")
    @dir = File.join(@store, "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md"),
               "---\nid: \"#{INTENT_ID}\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
    FileUtils.remove_entry(@repo) if @repo && Dir.exist?(@repo)
    Array(@scratch_dirs).each { |d| FileUtils.remove_entry(d) if d && Dir.exist?(d) }
  end

  # --- the git probe (row 5.12) ---------------------------------------------------
  #
  # A positive check, taken before any subprocess in the test body runs -
  # never a rescue wrapped around the subprocess call itself. A rescue there
  # would turn a genuine crash in the real CLI path into a green skip, which
  # is exactly the defect this whole node exists to catch (row 5.13).

  def git_available?
    system("git", "--version", out: File::NULL, err: File::NULL)
  end

  def assert_git_available!
    skip "git not available" unless git_available?
  end

  # --- fixture helpers (the same shapes runner_cli_test.rb and
  # runner_until_empty_test.rb already build a scratch intent from) --------------

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

  def write_lock(owner:)
    File.write(File.join(@dir, "delivery.lock"),
               JSON.generate("type" => "delivery", "owner_session" => owner, "delegates" => []))
  end

  def git(*args, dir: @repo)
    out, err, status = Open3.capture3("git", "-C", dir, *args.map(&:to_s))
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  # A real throwaway git repo, registered in projects.yml, with the intent
  # worktree already checked out on the intent branch, so RunnerDispatch can
  # actually provision a work node's own worktree and RunnerAbsorb can
  # actually merge it back. Never the real Plastic repository, never the
  # owner's real ~/.plastic.
  def setup_real_repo
    @repo = Dir.mktmpdir("dogfood-repo")
    git("init", "-q", "-b", "alpha")
    git("config", "user.email", "dogfood@example.com")
    git("config", "user.name", "Dogfood Test")
    git("config", "gc.auto", "0")
    File.write(File.join(@repo, "README.md"), "hi\n")
    git("add", "README.md")
    git("commit", "-q", "-m", "init")

    FileUtils.mkdir_p(File.join(@home, ".plastic"))
    File.write(File.join(@home, ".plastic", "projects.yml"),
               YAML.dump("projects" => { PROJECT_SLUG => { "path" => @repo } }))
    File.write(File.join(@home, ".plastic", "manifest.json"), JSON.generate("files" => {}))

    intent_worktree = File.join(@repo, ".claude", "worktrees", "#{INTENT_ID}--#{INTENT_SLUG}")
    intent_branch = "plastic/#{INTENT_ID}--#{INTENT_SLUG}"
    FileUtils.mkdir_p(File.dirname(intent_worktree))
    git("worktree", "add", intent_worktree, "-b", intent_branch, dir: @repo)
  end

  # One work node (n1) and one verify node (v1 needs n1) - the smallest
  # graph that can dispatch both kinds through the same CLI path (row 5.9).
  # `with_lock: false` builds the same intent with no delivery lock, the
  # fixture rows 5.10 and 5.13 need to force a real, well-understood
  # subprocess failure.
  def build_scratch_intent(with_lock: true)
    write_graph("- n1 needs nothing\n- v1 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work")
    write_node("v1.md", node: "v1", kind: "verify", body: "# v1 - review\n\n## Criteria\ndone\n")
    write_lock(owner: "sess-1") if with_lock
    setup_real_repo
  end

  def write_return(node, status:, commit:, summary: "ok")
    scratch = Dir.mktmpdir("dogfood-return")
    (@scratch_dirs ||= []) << scratch
    path = File.join(scratch, "#{node}.return")
    File.write(path, YAML.dump("node" => node, "status" => status, "commit" => commit, "summary" => summary))
    path
  end

  # --- driving the real CLI --------------------------------------------------------

  def run_cli(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => "sess-1" }
    Open3.capture3(env, RbConfig.ruby, SCRIPT, *args.map(&:to_s))
  end

  def run_step(*extra_args)
    run_cli("step", @dir, *extra_args)
  end

  def assert_cli_ok(out, err, status, label)
    assert status.success?, "#{label} failed:\n#{err}\n#{out}"
  end

  # Splits the rendered Claude blocks out of stdout: one match per
  # dispatched node, exactly the shape HarnessAdapter.render_claude_code
  # writes.
  def parsed_dispatch_blocks(out)
    out.scan(/Dispatch (\S+) for (\S+) \(model: ([^)]+)\):\n\s*prompt: (\S+)/)
  end

  # The YAML plan `step` always prints, from the leading `---` document
  # marker up to (not including) Runner::DOCUMENT_BOUNDARY, parsed back into
  # a Hash so a test can compare it against the rendered block underneath.
  def parsed_plan_yaml(out)
    lines = out.lines
    start_idx = lines.index { |l| l.start_with?("---") }
    boundary_idx = lines.index { |l| l.chomp == Runner::DOCUMENT_BOUNDARY }
    refute_nil start_idx, "expected a YAML plan in stdout:\n#{out}"
    refute_nil boundary_idx, "expected the document boundary marker in stdout:\n#{out}"
    YAML.safe_load(lines[start_idx...boundary_idx].join)
  end

  # --- 5.1: `runner status` on a scratch intent, as a subprocess ------------------

  def test_status_subprocess_runs
    assert_git_available!
    build_scratch_intent

    out, err, status = run_cli("status", @dir)
    assert_cli_ok(out, err, status, "runner status")
    assert_match(/\bn1\b/, out)
    assert_match(/\bv1\b/, out)
  end

  # --- 5.2: `runner step` on a scratch intent, as a subprocess --------------------

  def test_step_subprocess_dispatches
    assert_git_available!
    build_scratch_intent

    out, err, status = run_step
    assert_cli_ok(out, err, status, "runner step")
    assert_match(/Dispatch plastic-node-work for n1/, out)
  end

  # --- 5.3: the rendered agent type is a file under agents/ -----------------------

  def test_rendered_agent_type_exists_on_disk
    assert_git_available!
    build_scratch_intent

    out, err, status = run_step
    assert_cli_ok(out, err, status, "runner step")

    blocks = parsed_dispatch_blocks(out)
    refute_empty blocks, "the rendered block must name at least one dispatch:\n#{out}"
    blocks.each do |agent, _node, _model, _input|
      assert File.exist?(File.join(AGENTS_DIR, "#{agent}.md")),
             "#{agent.inspect} must be a real file under agents/"
    end
  end

  # --- 5.4: the rendered node input path exists ---------------------------------------

  def test_rendered_input_path_exists
    assert_git_available!
    build_scratch_intent

    out, err, status = run_step
    assert_cli_ok(out, err, status, "runner step")

    blocks = parsed_dispatch_blocks(out)
    refute_empty blocks, "the rendered block must name at least one dispatch:\n#{out}"
    blocks.each do |_agent, _node, _model, input|
      assert File.exist?(input), "the rendered node input path #{input.inspect} must exist on disk"
    end
  end

  # --- 5.5: the rendered model equals the plan's model -----------------------------

  def test_rendered_model_matches_plan
    assert_git_available!
    build_scratch_intent

    out, err, status = run_step
    assert_cli_ok(out, err, status, "runner step")

    plan = parsed_plan_yaml(out)
    plan_models = Array(plan["dispatch"]).each_with_object({}) { |d, h| h[d["node"]] = d["model"] }

    blocks = parsed_dispatch_blocks(out)
    refute_empty blocks, "the rendered block must name at least one dispatch:\n#{out}"
    blocks.each do |_agent, node, model, _input|
      assert_equal plan_models[node], model,
                   "the rendered block's model for #{node} must match the plan's own model"
    end
  end

  # --- 5.6: the running line carries harness=claude-code ---------------------------

  def test_running_line_records_claude_harness
    assert_git_available!
    build_scratch_intent

    out, err, status = run_step
    assert_cli_ok(out, err, status, "runner step")

    content = File.read(File.join(@dir, "savepoint.md"))
    running_line = content.lines.find { |l| l.include?("  n1  running") }
    refute_nil running_line, "expected a running line for n1:\n#{content}"
    assert_match(/harness=claude-code/, running_line)
  end

  # --- 5.7: the YAML plan above the block still parses as one document ------------

  def test_plan_still_parses_as_yaml
    assert_git_available!
    build_scratch_intent

    out, err, status = run_step
    assert_cli_ok(out, err, status, "runner step")

    plan = parsed_plan_yaml(out)
    assert_kind_of Hash, plan
    assert plan.key?("return_contract"), "the parsed plan must still carry the return contract"
    assert plan.key?("dispatch"), "the parsed plan must still carry the dispatch list"
  end

  # --- 5.8: runner-step.last exists after the step ---------------------------------

  def test_step_persists_last_output
    assert_git_available!
    build_scratch_intent

    out, err, status = run_step
    assert_cli_ok(out, err, status, "runner step")

    last_path = File.join(@dir, "runner-step.last")
    assert File.exist?(last_path), "runner-step.last must exist after a step"
    persisted = File.read(last_path)
    assert_match(/Dispatch plastic-node-work for n1/, persisted)
  end

  # --- 5.9: a verify node renders the read-only agent through the same path -------

  def test_verify_node_renders_read_only_agent
    assert_git_available!
    build_scratch_intent

    out1, err1, status1 = run_step
    assert_cli_ok(out1, err1, status1, "runner step (dispatch n1)")

    return_path = write_return("n1", status: "done", commit: "deadbeef")
    out2, err2, status2 = run_step("--return", "n1=#{return_path}")
    assert_cli_ok(out2, err2, status2, "runner step (absorb n1, dispatch v1)")

    blocks = parsed_dispatch_blocks(out2)
    verify_block = blocks.find { |_agent, node, *_rest| node == "v1" }
    refute_nil verify_block, "v1 must be dispatched once n1 is done:\n#{out2}"
    agent, = verify_block
    assert_equal "plastic-node-verify", agent
  end

  # --- 5.10: a nonzero subprocess exit fails with its stderr in the message -------

  def test_subprocess_failure_reports_stderr
    assert_git_available!
    build_scratch_intent

    out, err, status = run_step("--return", "bogus")
    refute status.success?, "a malformed --return pair must fail the subprocess"
    assert_match(/malformed --return/, err)

    failure = assert_raises(Minitest::Assertion) do
      assert_cli_ok(out, err, status, "runner step")
    end
    assert_includes failure.message, "malformed --return", "the assertion failure must carry the real stderr"
  end

  # --- 5.11: the scratch intent is hermetic ----------------------------------------

  def test_scratch_intent_is_hermetic
    assert_git_available!
    build_scratch_intent

    out, err, status = run_step
    assert_cli_ok(out, err, status, "runner step")

    assert_operator @home, :start_with?, Dir.tmpdir
    assert_operator @repo, :start_with?, Dir.tmpdir

    plan = parsed_plan_yaml(out)
    Array(plan["dispatch"]).each do |d|
      assert d["worktree"].to_s.start_with?(@repo),
             "a dispatched node's worktree must live under the scratch repo, not #{d['worktree'].inspect}"
      assert d["input"].to_s.start_with?(@home),
             "a dispatched node's input must live under the scratch home, not #{d['input'].inspect}"
    end

    written = Dir.glob(File.join(@dir, "**", "*"), File::FNM_DOTMATCH).reject { |p| File.directory?(p) }
    written.each do |path|
      resolved = File.expand_path(path)
      assert resolved.start_with?(File.expand_path(@home)),
             "the dogfood walk must never write outside its own tmpdir home: #{resolved}"
    end
  end

  # --- 5.12: a skip is gated on a positive environment probe taken first ----------

  def test_skip_is_gated_on_a_prior_git_probe
    no_git_dir = Dir.mktmpdir("no-git-on-path")
    (@scratch_dirs ||= []) << no_git_dir
    original_path = ENV["PATH"]
    probe = nil
    subprocess_attempted = false
    skipped = false

    begin
      ENV["PATH"] = no_git_dir
      probe = git_available?
      begin
        skip "git not available" unless probe
        subprocess_attempted = true
      rescue Minitest::Skip
        skipped = true
      end
    ensure
      ENV["PATH"] = original_path
    end

    refute probe, "the fixture must actually make git unavailable for this row to prove anything"
    assert skipped, "a negative probe must skip before any subprocess is attempted"
    refute subprocess_attempted, "no subprocess call may happen once the probe reads negative"
  end

  # --- 5.13: a real subprocess failure fails the test, never skips it -------------

  def test_subprocess_failure_never_skips
    assert_git_available!
    build_scratch_intent(with_lock: false)

    out, err, status = run_step
    refute status.success?, "a step with no lock held must fail"
    assert_match(/lock_not_held/, err)

    raised = nil
    begin
      assert_cli_ok(out, err, status, "runner step")
    rescue Minitest::Assertion => e
      raised = e
    end

    refute_nil raised, "a genuine subprocess failure must raise an assertion, never pass silently"
    refute_kind_of Minitest::Skip, raised, "a genuine subprocess failure must never read as a skip"
    assert_includes raised.message, "lock_not_held"
  end
end
