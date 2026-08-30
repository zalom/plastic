require "minitest/autorun"
require "tmpdir"
require "fileutils"

# spawn-preamble (intent 4a1c1) emits a deterministic live-state preamble for a
# spawned agent, built purely from the intent dir's filesystem state. These tests
# shell out to the script (the way a harness dispatch wrapper would) and assert it
# surfaces the intent id, intent name, current stage, and the no-hallucinate
# instruction, and that two runs are byte-identical.
class SpawnPreambleTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/spawn-preamble", __dir__)

  def setup
    @root = Dir.mktmpdir("spawn-preamble")
    @intent_dir = File.join(@root, "store", "4a1c1--agent-harness")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "4a1c1--agent-harness.md"), <<~MD)
      ---
      id: 4a1c1
      intent: Agent harness foundation
      sources: ["4a1c1"]
      chain: ["4a1c1"]
      created: 2026-06-18
      author: zlatko
      tags: [harness]
      ---

      ## Intent
      Build the harness.
    MD
    File.write(File.join(@intent_dir, "savepoint.md"),
               "2026-06-18T00:00:00Z  Why  spec.md created\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def run_script(*args)
    IO.popen(["ruby", SCRIPT, @intent_dir, *args], &:read)
  end

  def test_preamble_contains_intent_id_name_stage_and_instruction
    out = run_script("--role", "plastic-executor")

    assert_includes out, "4a1c1", "preamble must surface the intent id"
    assert_includes out, "Agent harness foundation", "preamble must surface the intent name"
    assert_includes out, "spec.md created", "preamble must surface the current stage (savepoint line)"
    assert_includes out, "plastic-executor", "preamble must surface the role"
    assert_includes out,
      "do not hallucinate intents or stages",
      "preamble must carry the no-hallucinate honoring instruction"
  end

  # intent 74: every dispatched agent must be told to end with a structured
  # completion report. Assert the verbatim REPORT_CONTRACT wording is emitted, so
  # the contract doc and role prompts have a single source of truth to agree with.
  def test_preamble_carries_report_contract
    out = run_script("--role", "plastic-executor")

    assert_includes out,
      "END your turn with a structured completion report as your FINAL MESSAGE",
      "preamble must carry the mandatory completion-report contract"
    assert_includes out,
      "the executor reports what was built and the test result",
      "report contract must name the per-role payload exemplar"
    # Intent 84: reports are prose-stripped (envelope + payload only).
    assert_includes out, "prose-stripped",
      "report contract must instruct subagents to strip conversational prose"
    # Intent 82: the report carries an insights field; bg/dispatched agents
    # populate it and the orchestrator persists via insight-append.
    assert_includes out, "insights field",
      "report contract must name the insights field"
    assert_includes out, "scripts/insight-append",
      "report contract must name insight-append as the persist path"
  end

  def test_stage_derived_from_files_when_no_savepoint
    FileUtils.rm_f(File.join(@intent_dir, "savepoint.md"))
    File.write(File.join(@intent_dir, "spec.md"), "spec\n")
    out = run_script

    # spec.md present, no plan -> How stage derived from files.
    assert_includes out, "Current stage: How"
  end

  def test_deterministic_across_runs
    first = run_script("--role", "plastic-executor")
    second = run_script("--role", "plastic-executor")
    assert_equal first, second, "two runs over identical state must be byte-identical"
  end

  def test_usage_error_without_intent_dir
    out = IO.popen(["ruby", SCRIPT], err: [:child, :out], &:read)
    assert_includes out, "usage:"
    refute_equal 0, $?.exitstatus
  end

  # Intent 152: no role file should hand-carry `EnterWorktree` prose. The
  # shared preamble is the single choke point; a hand-added instruction in a
  # role file would be a second, driftable source of truth. Green from day
  # one (a repo-wide grep already confirms zero hits outside the one code
  # comment in scripts/lib/worktree.rb); it starts failing only if someone
  # later reintroduces the literal string into a role file.
  def test_no_agent_role_file_hand_carries_enter_worktree_prose
    offenders = Dir[File.expand_path("../agents/*.md", __dir__)].select do |f|
      File.read(f).include?("EnterWorktree")
    end
    assert_empty offenders,
      "these role files hand-carry EnterWorktree prose instead of relying on " \
      "the shared spawn-preamble: #{offenders.map { |f| File.basename(f) }.join(', ')}"
  end

  # Intent 152, AC2 fail-open (negative case a): the existing fixture's store
  # path (@root/store/4a1c1--agent-harness) has no "projects" path segment, so
  # Worktree.slug_for_store already returns nil today. No code worktree lines
  # should ever appear for it.
  def test_no_worktree_lines_when_store_has_no_project_slug
    out = run_script("--role", "plastic-executor")
    refute_includes out, "Code worktree"
  end

  # Intent 152, AC2 fail-open (negative case b): a resolvable project slug and
  # a real repo path, but no `.claude/worktrees/<id>--<slug>` directory ever
  # created on disk. Still no code worktree lines.
  def test_no_worktree_lines_when_resolved_path_does_not_exist_on_disk
    home = Dir.mktmpdir("spawn-preamble-home")
    repo = Dir.mktmpdir("spawn-preamble-repo")
    begin
      project_dir = File.join(home, ".plastic", "projects", "demo", "store",
                               "4a1c1--agent-harness")
      FileUtils.mkdir_p(project_dir)
      File.write(File.join(project_dir, "4a1c1--agent-harness.md"), <<~MD)
        ---
        id: 4a1c1
        intent: Agent harness foundation
        sources: ["4a1c1"]
        chain: ["4a1c1"]
        created: 2026-06-18
        author: zlatko
        tags: [harness]
        ---

        ## Intent
        Build the harness.
      MD
      FileUtils.mkdir_p(File.join(home, ".plastic"))
      File.write(File.join(home, ".plastic", "projects.yml"), <<~YML)
        projects:
          demo:
            path: "#{repo}"
      YML
      # Deliberately do NOT create <repo>/.claude/worktrees/4a1c1--agent-harness.

      out = IO.popen({ "HOME" => home }, ["ruby", SCRIPT, project_dir, "--role", "plastic-executor"], &:read)
      refute_includes out, "Code worktree"
    ensure
      FileUtils.rm_rf(home)
      FileUtils.rm_rf(repo)
    end
  end

  # Intent 152, AC1/AC3: when the code worktree DOES exist on disk, the
  # preamble names its absolute path and an explicit cd-fallback instruction
  # for when EnterWorktree cannot discover the nested repo from a non-repo
  # launch directory. RED until scripts/spawn-preamble implements it.
  def test_worktree_lines_present_when_code_worktree_exists_on_disk
    home = Dir.mktmpdir("spawn-preamble-home")
    repo = Dir.mktmpdir("spawn-preamble-repo")
    begin
      out, worktree_path = run_with_provisioned_worktree(home, repo)

      assert_includes out, worktree_path,
        "preamble must surface the absolute code worktree path"
      assert_includes out, "EnterWorktree",
        "preamble must name EnterWorktree in the fallback instruction"
      assert_includes out, "cd",
        "preamble must instruct a direct cd fallback"
    ensure
      FileUtils.rm_rf(home)
      FileUtils.rm_rf(repo)
    end
  end

  # Intent 152, AC3: two runs over identical on-disk state, INCLUDING the
  # worktree-lines-present branch, stay byte-identical. Extends coverage
  # without touching the existing test_deterministic_across_runs fixture.
  def test_deterministic_across_runs_with_worktree_lines_present
    home = Dir.mktmpdir("spawn-preamble-home")
    repo = Dir.mktmpdir("spawn-preamble-repo")
    begin
      first, = run_with_provisioned_worktree(home, repo)
      second, = run_with_provisioned_worktree(home, repo)
      assert_equal first, second,
        "two runs over identical state, including worktree lines, must be byte-identical"
    ensure
      FileUtils.rm_rf(home)
      FileUtils.rm_rf(repo)
    end
  end

  private

  # Builds a fake HOME with a projects.yml entry resolving to a fake repo, a
  # copy of the intent + savepoint under the project's tactical store, and the
  # `.claude/worktrees/<id>--<slug>` directory already provisioned on disk (no
  # `git init` needed: the new code path only calls Dir.exist?, never a git
  # shell-out). Returns [script_output, absolute_worktree_path].
  def run_with_provisioned_worktree(home, repo)
    project_dir = File.join(home, ".plastic", "projects", "demo", "store",
                             "4a1c1--agent-harness")
    FileUtils.mkdir_p(project_dir)
    File.write(File.join(project_dir, "4a1c1--agent-harness.md"), <<~MD)
      ---
      id: 4a1c1
      intent: Agent harness foundation
      sources: ["4a1c1"]
      chain: ["4a1c1"]
      created: 2026-06-18
      author: zlatko
      tags: [harness]
      ---

      ## Intent
      Build the harness.
    MD
    File.write(File.join(project_dir, "savepoint.md"),
               "2026-06-18T00:00:00Z  Exec  actions in progress\n")
    FileUtils.mkdir_p(File.join(home, ".plastic"))
    File.write(File.join(home, ".plastic", "projects.yml"), <<~YML)
      projects:
        demo:
          path: "#{repo}"
    YML

    worktree_path = File.join(repo, ".claude", "worktrees", "4a1c1--agent-harness")
    FileUtils.mkdir_p(worktree_path)

    out = IO.popen({ "HOME" => home }, ["ruby", SCRIPT, project_dir, "--role", "plastic-executor"], &:read)
    [out, worktree_path]
  end
end
