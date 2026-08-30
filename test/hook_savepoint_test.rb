# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/handoff"

# Intent 311: the PreCompact hook. `hooks/savepoint` is a bash launcher over
# `scripts/hook-savepoint`, which writes this session's hand-off for the
# pointer's day and prints one static message. Every run is a subprocess with
# a throwaway HOME and PLASTIC_HOME; nothing here touches the real store.
class HookSavepointTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  SCRIPT = File.join(REPO, "scripts", "hook-savepoint")
  LAUNCHER = File.join(REPO, "hooks", "savepoint")
  TEMPLATES = File.join(REPO, "templates")
  DAY = "20260830"
  SID = "b7137962-dead-beef"
  SHORT = "b7137962"

  def setup
    @home = Dir.mktmpdir("hook-savepoint-home")
    @plastic_home = File.join(@home, ".plastic")
    @store = File.join(@plastic_home, "store")
    FileUtils.mkdir_p(@store)
    SessionLedger.open_day(store: @store, day: DAY, templates: TEMPLATES, author: "t")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def pointer(value, session: SHORT)
    SessionLedger.ensure_tmp_root(@store)
    FileUtils.mkdir_p(SessionLedger.session_tmp_dir(@store, session))
    File.write(SessionLedger.pointer_path(@store, session), "#{value}\n")
  end

  def payload(session_id: SID)
    JSON.generate("session_id" => session_id, "cwd" => @home, "hook_event_name" => "PreCompact",
                  "trigger" => "auto")
  end

  def env
    { "HOME" => @home, "PLASTIC_HOME" => @plastic_home, "CLAUDE_CODE_SESSION_ID" => nil }
  end

  def run_script(stdin)
    Open3.capture3(env, RbConfig.ruby, SCRIPT, @plastic_home, stdin_data: stdin)
  end

  def run_launcher(stdin)
    Open3.capture3(env, LAUNCHER, stdin_data: stdin)
  end

  def handoff_path
    Handoff.path_for(@store, DAY, SHORT)
  end

  def message_of(out)
    JSON.parse(out)["systemMessage"]
  end

  # --- the script ------------------------------------------------------------------

  def test_writes_the_handoff_for_the_pointer_day_and_prints_the_static_message
    pointer(DAY)
    SessionLedger.append_line(SessionLedger.checklist_path(@store, DAY),
                              SessionLedger.checklist_line(:open, SHORT, "plastic", "mid-flight"),
                              header: SessionLedger.checklist_header(DAY))
    out, err, status = run_script(payload)
    assert_equal 0, status.exitstatus, err
    assert File.exist?(handoff_path), "hand-off must be written"
    text = File.read(handoff_path)
    assert_includes text, "at precompact"
    assert_includes text, "mid-flight"
    message = message_of(out)
    assert_includes message, "PLASTIC SAVEPOINT"
    assert_includes message, "handoff--<session>.md"
    assert_includes message, "say continue"
    assert_includes message, "This session's file: #{handoff_path}"
  end

  def test_message_without_a_session_is_the_fixed_text_and_names_no_file
    first, = run_script("")
    second, = run_script(payload(session_id: ""))
    assert_equal first, second, "the message must not vary when no session resolves"
    refute_includes message_of(first), "This session's file"
  end

  def test_malformed_stdin_exits_0_prints_the_message_and_writes_nothing
    pointer(DAY)
    out, _err, status = run_script("{not json")
    assert_equal 0, status.exitstatus
    assert_includes message_of(out), "PLASTIC SAVEPOINT"
    refute File.exist?(handoff_path)
  end

  def test_empty_stdin_exits_0_and_prints_the_message
    out, _err, status = run_script("")
    assert_equal 0, status.exitstatus
    assert_includes message_of(out), "PLASTIC SAVEPOINT"
  end

  def test_no_session_id_writes_nothing
    pointer(DAY)
    out, _err, status = run_script(payload(session_id: ""))
    assert_equal 0, status.exitstatus
    assert_includes message_of(out), "PLASTIC SAVEPOINT"
    refute File.exist?(handoff_path)
    refute File.exist?(Handoff.path_for(@store, DAY, "local"))
  end

  # An auto team's session points at its intent; its hand-off goes to today's
  # day directory, the same fallback the close uses (review finding 1).
  def test_pointer_naming_an_intent_writes_todays_handoff
    pointer("311--handoff-and-day-summary")
    out, _err, status = run_script(payload)
    assert_equal 0, status.exitstatus
    assert_includes message_of(out), "PLASTIC SAVEPOINT"
    today = SessionLedger.day_id
    assert File.exist?(Handoff.path_for(@store, today, SHORT)), "hand-off must land in today's day dir"
    refute File.exist?(handoff_path) unless today == DAY
  end

  def test_missing_plastic_home_argument_still_prints_the_message
    out, _err, status = Open3.capture3(env, RbConfig.ruby, SCRIPT, stdin_data: payload)
    assert_equal 0, status.exitstatus
    assert_includes message_of(out), "PLASTIC SAVEPOINT"
  end

  # --- the launcher ---------------------------------------------------------------

  def test_launcher_pipes_stdin_and_resolves_the_store_off_home
    pointer(DAY)
    out, err, status = run_launcher(payload)
    assert_equal 0, status.exitstatus, err
    assert File.exist?(handoff_path), "the launcher must reach the script with the payload"
    assert_includes message_of(out), "PLASTIC SAVEPOINT"
  end

  def test_launcher_no_longer_carries_the_1x_instruction_block
    src = File.read(LAUNCHER)
    refute_includes src, ".plastic/INDEX.md"
    refute_includes src, "Build/Observe"
    refute_includes src, "savepoint procedure"
    assert_includes src, "scripts/hook-savepoint"
    assert_includes src, "[ -t 0 ] || INPUT=$(cat)", "the launcher must not block on a tty"
  end

  # --- the prose the hook depends on -----------------------------------------------

  def test_reading_the_ledgers_guide_names_the_handoff_and_the_day_summary
    guide = File.read(File.join(REPO, "docs", "guides", "reading-the-ledgers.md"))
    assert_includes guide, "handoff--"
    assert_includes guide.downcase, "day summary"
  end

  def test_intent_continuing_reads_the_day_directory_handoff_not_a_per_intent_one
    skill = File.read(File.join(REPO, "skills", "intent-continuing", "SKILL.md"))
    refute_includes skill, "resources/handoff", "nothing writes a per-intent hand-off (spec D11)"
    assert_includes skill, ".sessions/"
  end
end
