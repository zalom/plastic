require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/db"

# Regression for intent 52: the savepoint ledger must be written even when no
# bridge exists and no session id present. The savepoint is derived from the
# file path, decoupled from bridge resolution. Cutover intent 41 ACTION_11:
# the ledger lands in `savepoint_events`, not savepoint.md.
class GateCheckTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-gate-check", __dir__)

  def setup
    @root = Dir.mktmpdir("gate-check")
    @store = File.join(@root, "store")
    @intent_dir = File.join(@store, "52--x")
    FileUtils.mkdir_p(@intent_dir)
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    # Clear so a real ambient session id cannot leak into a "no id" case.
    ENV.delete("CLAUDE_CODE_SESSION_ID")
  end

  def teardown
    FileUtils.rm_rf(@root)
    restore_env("CLAUDE_CODE_SESSION_ID", @saved_session)
  end

  def restore_env(key, saved)
    saved.nil? ? ENV.delete(key) : ENV[key] = saved
  end

  def run_hook(file_path, session: nil)
    # PLASTIC_STORE_HOME isolates the hook's discover_bridge call (used only
    # for stage-transition tracking, exercised elsewhere): without it, cwd
    # resolution would fall through to the REAL ~/.plastic.
    env = { "CLAUDE_CODE_SESSION_ID" => session, "PLASTIC_STORE_HOME" => @root }
    out = IO.popen(env, ["ruby", SCRIPT, file_path], &:read)
    [out, $?]
  end

  def pairs
    conn = Plastic::DB.connect(@root)
    Plastic::DB::SavepointEvents.events_for(conn, "52").map { |e| [e["stage"], e["event_type"]] }
  end

  def test_savepoint_written_without_bridge_or_session
    # What milestone file: <id>--<slug>.md
    intent_file = File.join(@intent_dir, "52--x.md")
    File.write(intent_file, "## Intent\nx\n")
    spec = File.join(@intent_dir, "spec.md")
    File.write(spec, "spec\n")

    out, status = run_hook(spec)

    assert_equal 0, status.exitstatus, "hook should exit 0, got: #{out}"
    assert_includes pairs, ["Why", "spec.md created"]
  end

  def test_savepoint_idempotent_across_runs
    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    spec = File.join(@intent_dir, "spec.md")
    File.write(spec, "spec\n")

    run_hook(spec)
    run_hook(spec)
    assert_equal 1, pairs.count { |p| p == ["Why", "spec.md created"] }
  end

  # --- Intent 81: checklist.md landing emits the Exec-started companion -------

  def test_checklist_landing_emits_exec_started
    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    checklist = File.join(@intent_dir, "checklist.md")
    File.write(checklist, "# Checklist\nreal\n")

    out, status = run_hook(checklist)
    assert_equal 0, status.exitstatus, "hook should exit 0, got: #{out}"

    assert_includes pairs, ["How", "checklist.md created"]
    assert_includes pairs, ["Exec", "started"], "checklist landing must emit the Exec-started companion"
  end

  def test_exec_started_not_emitted_for_placeholder_checklist
    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    checklist = File.join(@intent_dir, "checklist.md")
    File.write(checklist, "#{Bridge::PLACEHOLDER_SENTINEL}\n\nplaceholder\n")

    run_hook(checklist)
    refute_includes pairs, ["Exec", "started"], "a sentinel checklist must not emit Exec started"
  end

  # --- Gate-milestone export + commit (D5/AC8) --------------------------------

  def test_gate_milestone_export_commits_savepoint_jsonl
    system("git", "-C", @root, "init", "-q", out: File::NULL, err: File::NULL)
    system("git", "-C", @root, "config", "user.email", "test@example.com")
    system("git", "-C", @root, "config", "user.name", "Test")
    File.write(File.join(@root, ".seed"), "seed\n")
    system("git", "-C", @root, "add", "-A", out: File::NULL, err: File::NULL)
    system("git", "-C", @root, "commit", "-q", "-m", "seed", out: File::NULL, err: File::NULL)

    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    spec = File.join(@intent_dir, "spec.md")
    File.write(spec, "spec\n")

    run_hook(spec)

    export_path = File.join(@intent_dir, "savepoint.jsonl")
    assert File.exist?(export_path), "a gate milestone must export savepoint.jsonl"

    log = `git -C #{@root} log --oneline -- #{export_path.sub("#{@root}/", "")}`
    refute_empty log.strip, "the exported savepoint.jsonl must be committed in the store repo"
  end

  def test_non_gate_started_event_does_not_export
    File.write(File.join(@intent_dir, "52--x.md"), "## Intent\nx\n")
    plan = File.join(@intent_dir, "plan.md")
    # Pre-hook stamps "How started" (not a gate milestone) via hook-savepoint-pre
    # in the real flow; here we drive gate-check directly on a non-milestone
    # write to confirm no export fires for a non-lifecycle path.
    other = File.join(@intent_dir, "resources", "note.md")
    FileUtils.mkdir_p(File.dirname(other))
    File.write(other, "x\n")
    run_hook(other)
    refute File.exist?(File.join(@intent_dir, "savepoint.jsonl"))
  end
end
