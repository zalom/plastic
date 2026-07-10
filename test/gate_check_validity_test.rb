require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/db"

# Intent 4a1c1: hook-gate-check runs IntentValidator on the intent file itself as
# an artifact-validity backstop. Invalid intent file -> loud non-zero (the
# PostToolUse rejection signal, since the write already happened). Valid intent
# file -> exit 0 with the What savepoint stamped (cutover intent 41 ACTION_11:
# into `savepoint_events`, not savepoint.md). Non-intent lifecycle files
# (spec.md, etc.) keep their existing behavior, untouched by this backstop.
class GateCheckValidityTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-gate-check", __dir__)

  def setup
    @root = Dir.mktmpdir("gate-validity")
    @store = File.join(@root, "store")
    @intent_dir = File.join(@store, "4a1c1--agent-harness")
    FileUtils.mkdir_p(@intent_dir)
    @saved_session = ENV["CLAUDE_CODE_SESSION_ID"]
    ENV.delete("CLAUDE_CODE_SESSION_ID")
  end

  def teardown
    FileUtils.rm_rf(@root)
    restore_env("CLAUDE_CODE_SESSION_ID", @saved_session)
  end

  def restore_env(key, saved)
    saved.nil? ? ENV.delete(key) : ENV[key] = saved
  end

  def intent_file
    File.join(@intent_dir, "4a1c1--agent-harness.md")
  end

  def valid_frontmatter
    <<~MD
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

      ## Context
      Why this exists.

      ## Outcome
      The result.

      ## Insights
      Observations.

      ## Links
      - none
    MD
  end

  def run_hook(file_path)
    # PLASTIC_STORE_HOME isolates the hook's discover_bridge call: without it,
    # cwd resolution would fall through to the REAL ~/.plastic.
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_STORE_HOME" => @root }
    out = IO.popen(env, ["ruby", SCRIPT, file_path], err: [:child, :out], &:read)
    [out, $?]
  end

  def pairs
    conn = Plastic::DB.connect(@root)
    Plastic::DB::SavepointEvents.events_for(conn, "4a1c1").map { |e| [e["stage"], e["event_type"]] }
  end

  def test_invalid_intent_file_exits_nonzero_with_message
    # Missing required fields (sources, chain, created, author, tags).
    File.write(intent_file, "---\nid: 4a1c1\nintent: x\n---\n\n## Intent\nx\n")
    out, status = run_hook(intent_file)

    refute_equal 0, status.exitstatus, "invalid intent file must exit non-zero"
    assert_includes out, "PLASTIC ARTIFACT INVALID"
    assert_includes out, "sources", "the failing field(s) must be named"
  end

  def test_valid_intent_file_exits_zero_and_stamps_savepoint
    File.write(intent_file, valid_frontmatter)
    out, status = run_hook(intent_file)

    assert_equal 0, status.exitstatus, "valid intent file must exit 0, got: #{out}"
    assert_includes pairs, ["What", "4a1c1--agent-harness.md"], "What milestone savepoint must be stamped"
  end

  def test_non_intent_lifecycle_file_behaviour_unchanged
    # A valid intent file must exist for the spec savepoint mapping to resolve.
    File.write(intent_file, valid_frontmatter)
    spec = File.join(@intent_dir, "spec.md")
    File.write(spec, "spec\n")

    out, status = run_hook(spec)

    assert_equal 0, status.exitstatus, "spec.md must keep exit 0, got: #{out}"
    refute_includes out, "PLASTIC ARTIFACT INVALID",
      "validity backstop must not fire for non-intent files"
    assert_includes pairs, ["Why", "spec.md created"]
  end

  def test_invalid_intent_file_does_not_fire_for_spec_even_if_intent_invalid
    # Backstop is keyed on the written file being the intent file, not on intent
    # validity in general: writing spec.md must not be rejected for a bad intent.
    File.write(intent_file, "---\nid: 4a1c1\nintent: x\n---\n\n## Intent\nx\n")
    spec = File.join(@intent_dir, "spec.md")
    File.write(spec, "spec\n")

    out, status = run_hook(spec)

    assert_equal 0, status.exitstatus
    refute_includes out, "PLASTIC ARTIFACT INVALID"
  end
end
