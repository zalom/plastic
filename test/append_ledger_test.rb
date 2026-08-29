# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "date"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/intent_validator"

# append-ledger has no .rb extension (it is a chmod +x script with a shebang),
# so require_relative cannot resolve it; `load` takes the literal path. Its
# `main(ARGV) if $PROGRAM_NAME == __FILE__` guard means loading it here only
# defines its top-level methods (used below to exercise run_transition
# in-process) without running its CLI.
load File.expand_path("../scripts/append-ledger", __dir__)

# Intent 297, task 3: scripts/append-ledger, driven as a real subprocess.
# Every spawn is hermetic: a Dir.mktmpdir store and PLASTIC_TMP, an explicit
# --session, and CLAUDE_CODE_SESSION_ID cleared in the child environment.
class AppendLedgerTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/append-ledger", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)
  SESSION = "b7137962"

  def setup
    @home = Dir.mktmpdir("append-ledger-home")
    @tmp = Dir.mktmpdir("append-ledger-tmp")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    @day = "20260829"
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def run_append(*args, env: {})
    base = {
      "CLAUDE_CODE_SESSION_ID" => nil,
      "PLASTIC_HOME" => @home,
      "PLASTIC_TMP" => @tmp,
    }
    full_args = [RbConfig.ruby, SCRIPT, "--store", @store, "--templates", TEMPLATES,
                 "--day", @day, "--session", SESSION, "--project", "plastic", *args]
    out = IO.popen(base.merge(env), full_args, err: [:child, :out], &:read)
    [out, $?.exitstatus]
  end

  def checklist_path
    SessionLedger.checklist_path(@store, @day)
  end

  def savepoint_path
    SessionLedger.savepoint_path(@store, @day)
  end

  # --- pending / item -----------------------------------------------------------

  def test_pending_creates_checklist_with_header_and_byte_exact_line
    _, status = run_append("pending", "Change how titles appear on the resume page")
    assert_equal 0, status

    lines = File.read(checklist_path).lines
    assert_equal "# Checklist: session ledger #{@day}\n", lines[0]
    assert_equal "\n", lines[1]
    assert_equal "- [~] [#{SESSION}] [plastic] Change how titles appear on the resume page\n", lines[2]
  end

  def test_item_appends_byte_exact_open_line
    run_append("pending", "seed")
    _, status = run_append("item", "Change how titles appear on the resume page")
    assert_equal 0, status

    lines = File.read(checklist_path).lines
    assert_equal "- [ ] [#{SESSION}] [plastic] Change how titles appear on the resume page\n", lines.last
  end

  # --- savepoint -----------------------------------------------------------------

  def test_savepoint_note_creates_file_with_no_header
    _, status = run_append("savepoint", "--event", "Note", "A free-form note")
    assert_equal 0, status

    content = File.read(savepoint_path)
    refute_match(/\A# Checklist/, content)
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ  Note  \[#{SESSION}\] \[plastic\] A free-form note\n\z/, content)
  end

  # --- promote / tick ---------------------------------------------------------------

  def test_promote_flips_newest_pending_of_caller_session
    run_append("pending", "First item")
    _, status = run_append("promote")
    assert_equal 0, status

    parsed = SessionLedger.parse_checklist_line(File.read(checklist_path).lines.last)
    assert_equal :open, parsed[:state]
  end

  def test_tick_flips_newest_open_of_caller_session
    run_append("pending", "First item")
    run_append("promote")
    _, status = run_append("tick")
    assert_equal 0, status

    parsed = SessionLedger.parse_checklist_line(File.read(checklist_path).lines.last)
    assert_equal :done, parsed[:state]
  end

  def test_promote_with_match_targets_only_matching_summary
    run_append("pending", "About the resume page")
    run_append("pending", "About something else")

    run_append("promote", "--match", "resume")

    lines = File.read(checklist_path).lines.map { |l| SessionLedger.parse_checklist_line(l) }.compact
    resume = lines.find { |l| l[:summary].include?("resume") }
    other = lines.find { |l| l[:summary].include?("something else") }

    assert_equal :open, resume[:state]
    assert_equal :pending, other[:state]
  end

  def test_promote_with_nothing_to_address_exits_2_and_leaves_file_unchanged
    run_append("pending", "seed")
    before = File.binread(checklist_path)

    _, status = run_append("promote", "--match", "nonexistent")
    after = File.binread(checklist_path)

    assert_equal 2, status
    assert_equal before, after
  end

  def test_tick_with_nothing_to_address_exits_2_and_leaves_file_unchanged
    run_append("pending", "seed")
    before = File.binread(checklist_path)

    _, status = run_append("tick")
    after = File.binread(checklist_path)

    assert_equal 2, status
    assert_equal before, after
  end

  def test_promote_savepoint_writes_flipped_byte_and_item_savepoint_line
    run_append("pending", "Change how titles appear on the resume page")
    _, status = run_append("promote", "--savepoint")
    assert_equal 0, status

    parsed = SessionLedger.parse_checklist_line(File.read(checklist_path).lines.last)
    assert_equal :open, parsed[:state]

    savepoint_content = File.read(savepoint_path)
    assert_match(/  Item  \[#{SESSION}\] \[plastic\] Change how titles appear on the resume page\n\z/, savepoint_content)
  end

  def test_tick_savepoint_writes_done_savepoint_line
    run_append("pending", "Some item")
    run_append("promote")
    _, status = run_append("tick", "--savepoint")
    assert_equal 0, status

    savepoint_content = File.read(savepoint_path)
    assert_match(/  Done  \[#{SESSION}\] \[plastic\] Some item\n\z/, savepoint_content)
  end

  def test_a_line_from_another_session_is_not_addressed
    other_session_out = nil
    IO.popen({ "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_HOME" => @home, "PLASTIC_TMP" => @tmp },
             [RbConfig.ruby, SCRIPT, "--store", @store, "--templates", TEMPLATES, "--day", @day,
              "--session", "aaaaaaaa", "--project", "plastic", "pending", "Owned by another session"],
             err: [:child, :out]) { |io| other_session_out = io.read }
    other_status = $?.exitstatus
    assert_equal 0, other_status, other_session_out

    _, status = run_append("promote")
    assert_equal 2, status, "own session's promote must not address the other session's line: #{other_session_out}"
  end

  # --- savepoint verb errors --------------------------------------------------------

  def test_savepoint_with_bogus_event_exits_2
    _, status = run_append("savepoint", "--event", "Bogus", "text")
    assert_equal 2, status
  end

  def test_empty_summary_exits_2
    _, status = run_append("pending", "   ")
    assert_equal 2, status
  end

  # --- --day validation --------------------------------------------------------------

  def test_day_with_dashes_exits_2
    out, status = run_append("pending", "seed", "--day", "2026-08-29")
    assert_equal 2, status, out
  end

  def test_day_with_invalid_calendar_date_exits_2
    out, status = run_append("pending", "seed", "--day", "20261340")
    assert_equal 2, status, out
  end

  # --- the midnight crossing ----------------------------------------------------------

  def test_missing_day_dir_is_scaffolded_by_append_ledger_itself
    refute Dir.exist?(SessionLedger.day_dir(@store, @day))

    _, status = run_append("pending", "First item of the day")
    assert_equal 0, status

    day_file = SessionLedger.day_file(@store, @day)
    assert File.exist?(day_file)
    validation = IntentValidator.validate(SessionLedger.day_dir(@store, @day))
    assert validation[:ok], validation[:errors].join(", ")

    parsed = SessionLedger.parse_checklist_line(File.read(checklist_path).lines.last)
    assert_equal "First item of the day", parsed[:summary]
  end

  def test_missing_day_dir_is_scaffolded_for_an_explicit_past_day
    yesterday = (Date.today - 1).strftime("%Y%m%d")
    refute Dir.exist?(SessionLedger.day_dir(@store, yesterday))

    _, status = run_append("pending", "Crossed midnight", "--day", yesterday)
    assert_equal 0, status
    assert File.exist?(SessionLedger.day_file(@store, yesterday))
  end

  # --- --project validation (finding 2) -----------------------------------------------

  def test_project_with_invalid_characters_exits_2
    out, status = run_append("pending", "seed", "--project", "evil] [pwned")
    assert_equal 2, status, out
  end

  def test_project_with_uppercase_exits_2
    out, status = run_append("pending", "seed", "--project", "Not-Valid")
    assert_equal 2, status, out
  end

  def test_project_with_a_newline_exits_2_and_never_corrupts_the_file
    out, status = run_append("pending", "seed", "--project", "a\nb")
    assert_equal 2, status, out
    refute File.exist?(checklist_path), "an invalid --project must never reach a write"
  end

  # --- templates dir guard (finding 4) ------------------------------------------------

  def test_missing_templates_dir_exits_2_rather_than_wedging_the_day
    out, status = run_append("pending", "seed", "--templates", File.join(@home, "no-such-templates"))
    assert_equal 2, status, out
    refute File.exist?(SessionLedger.day_file(@store, @day))
  end

  # --- append-ledger scaffolds even when the day dir exists without its md file (finding 5) --

  def test_append_ledger_scaffolds_when_day_dir_exists_without_its_md_file
    FileUtils.mkdir_p(SessionLedger.day_dir(@store, @day))
    refute File.exist?(SessionLedger.day_file(@store, @day))

    _, status = run_append("pending", "seed after an orphan day dir")
    assert_equal 0, status

    assert File.exist?(SessionLedger.day_file(@store, @day))
    validation = IntentValidator.validate(SessionLedger.day_dir(@store, @day))
    assert validation[:ok], validation[:errors].join(", ")
  end

  # --- a trailing flag with no value (nit 10) ------------------------------------------

  def test_trailing_flag_with_no_value_exits_2
    out, status = run_append("pending", "seed", "--store")
    assert_equal 2, status, out
  end

  # --- LockUnavailableError maps to exit 3 (nit 7) --------------------------------------
  #
  # append-ledger's own run_transition, called in-process (this file requires
  # scripts/append-ledger directly; its guarded `main(ARGV) if $PROGRAM_NAME
  # == __FILE__` never fires under a test runner). SessionLedger.set_state is
  # replaced with a raising stand-in for the duration of this one test only,
  # then always restored in ensure: minitest 6 dropped minitest/mock, so this
  # is a plain define_singleton_method swap rather than Object#stub.
  def test_run_transition_maps_lock_unavailable_error_to_exit_3
    FileUtils.mkdir_p(SessionLedger.day_dir(@store, @day))
    line = SessionLedger.checklist_line(:pending, SESSION, "plastic", "seed")
    File.write(checklist_path, SessionLedger.checklist_header(@day) + line)

    original_set_state = SessionLedger.method(:set_state)
    SessionLedger.define_singleton_method(:set_state) do |*|
      raise SessionLedger::LockUnavailableError, "no flock"
    end

    opts = { match: nil, savepoint: false }
    exit_code =
      begin
        run_transition(:pending, :open, "Item", @store, @day, SESSION, "plastic", opts)
        nil
      rescue SystemExit => e
        e.status
      end

    assert_equal 3, exit_code
  ensure
    SessionLedger.define_singleton_method(:set_state, original_set_state) if original_set_state
  end

  # --- no sibling lock file ------------------------------------------------------------

  def test_no_sibling_lock_file_after_a_full_sequence
    run_append("pending", "seed")
    run_append("promote", "--savepoint")
    run_append("tick", "--savepoint")
    run_append("savepoint", "--event", "Note", "a note")

    entries = Dir.children(SessionLedger.day_dir(@store, @day))
    refute entries.any? { |e| e.end_with?(".lock") }
  end
end
