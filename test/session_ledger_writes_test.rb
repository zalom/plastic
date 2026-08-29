# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/intent_validator"
require_relative "../scripts/lib/links_projection"

# Intent 297, task 2: the locked-write half of SessionLedger (append_line,
# set_state, read_locked) and the day scaffold (open_day). No process
# spawning: everything runs in process against a Dir.mktmpdir store.
class SessionLedgerWritesTest < Minitest::Test
  LIB_PATH = File.expand_path("../scripts/lib/session_ledger.rb", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)

  def setup
    @store = Dir.mktmpdir("session-ledger-writes")
    @day = "20260829"
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  def checklist_path
    SessionLedger.checklist_path(@store, @day)
  end

  def savepoint_path
    SessionLedger.savepoint_path(@store, @day)
  end

  def append_checklist_line(state, session, project, summary)
    FileUtils.mkdir_p(File.dirname(checklist_path))
    line = SessionLedger.checklist_line(state, session, project, summary)
    SessionLedger.append_line(checklist_path, line, header: SessionLedger.checklist_header(@day))
  end

  # --- the one-byte guarantee -------------------------------------------------

  def test_set_state_promote_changes_exactly_one_byte
    append_checklist_line(:pending, "b7137962", "plastic", "First item")
    append_checklist_line(:pending, "b7137962", "plastic", "Second item")

    before = File.binread(checklist_path)
    result = SessionLedger.set_state(checklist_path, from: :pending, to: :open, session: "b7137962")
    after = File.binread(checklist_path)

    assert result
    assert_equal before.bytesize, after.bytesize
    diff_indexes = (0...before.bytesize).select { |i| before.getbyte(i) != after.getbyte(i) }
    assert_equal 1, diff_indexes.length
  end

  def test_set_state_tick_changes_exactly_one_byte
    append_checklist_line(:open, "b7137962", "plastic", "Some item")

    before = File.binread(checklist_path)
    result = SessionLedger.set_state(checklist_path, from: :open, to: :done, session: "b7137962")
    after = File.binread(checklist_path)

    assert result
    assert_equal before.bytesize, after.bytesize
    diff_indexes = (0...before.bytesize).select { |i| before.getbyte(i) != after.getbyte(i) }
    assert_equal 1, diff_indexes.length
  end

  # --- addressing --------------------------------------------------------------

  def test_set_state_targets_newest_matching_line_of_the_caller_session
    append_checklist_line(:pending, "aaaaaaaa", "plastic", "Other session item")
    append_checklist_line(:pending, "b7137962", "plastic", "Older own item")
    append_checklist_line(:pending, "b7137962", "plastic", "Newer own item")

    SessionLedger.set_state(checklist_path, from: :pending, to: :open, session: "b7137962")

    lines = File.read(checklist_path).lines.map { |l| SessionLedger.parse_checklist_line(l) }.compact
    newer = lines.find { |l| l[:summary] == "Newer own item" }
    older = lines.find { |l| l[:summary] == "Older own item" }
    other = lines.find { |l| l[:summary] == "Other session item" }

    assert_equal :open, newer[:state]
    assert_equal :pending, older[:state]
    assert_equal :pending, other[:state]
  end

  def test_set_state_with_match_narrows_to_summary_substring
    append_checklist_line(:pending, "b7137962", "plastic", "About the resume page")
    append_checklist_line(:pending, "b7137962", "plastic", "About something else")

    SessionLedger.set_state(checklist_path, from: :pending, to: :open, session: "b7137962", match: "resume")

    lines = File.read(checklist_path).lines.map { |l| SessionLedger.parse_checklist_line(l) }.compact
    resume = lines.find { |l| l[:summary].include?("resume") }
    other = lines.find { |l| l[:summary].include?("something else") }

    assert_equal :open, resume[:state]
    assert_equal :pending, other[:state]
  end

  def test_set_state_returns_false_and_writes_nothing_when_no_match
    append_checklist_line(:pending, "aaaaaaaa", "plastic", "Some item")
    before = File.binread(checklist_path)

    result = SessionLedger.set_state(checklist_path, from: :pending, to: :open, session: "b7137962")
    after = File.binread(checklist_path)

    refute result
    assert_equal before, after
  end

  # --- the header ---------------------------------------------------------------

  def test_first_append_writes_the_checklist_header_then_blank_line
    append_checklist_line(:pending, "b7137962", "plastic", "First item")
    content = File.read(checklist_path)
    lines = content.lines

    assert_equal "# Checklist: session ledger #{@day}\n", lines[0]
    assert_equal "\n", lines[1]
  end

  def test_second_append_adds_no_second_header
    append_checklist_line(:pending, "b7137962", "plastic", "First item")
    append_checklist_line(:pending, "b7137962", "plastic", "Second item")

    content = File.read(checklist_path)
    assert_equal 1, content.scan("# Checklist: session ledger #{@day}").length
  end

  def test_savepoint_append_writes_no_header
    FileUtils.mkdir_p(File.dirname(savepoint_path))
    line = SessionLedger.savepoint_line("Note", "b7137962", "plastic", "A note", now: Time.now)
    SessionLedger.append_line(savepoint_path, line, header: nil)

    content = File.read(savepoint_path)
    refute_match(/\A# Checklist/, content)
    assert_equal line, content
  end

  # --- the lock target ------------------------------------------------------------

  def test_no_sibling_lock_file_exists_after_writes
    append_checklist_line(:pending, "b7137962", "plastic", "First item")
    SessionLedger.set_state(checklist_path, from: :pending, to: :open, session: "b7137962")

    entries = Dir.children(File.dirname(checklist_path))
    refute entries.any? { |e| e.end_with?(".lock") }
  end

  def test_inode_stays_stable_across_a_write
    append_checklist_line(:pending, "b7137962", "plastic", "First item")
    ino_before = File.stat(checklist_path).ino

    SessionLedger.set_state(checklist_path, from: :pending, to: :open, session: "b7137962")
    ino_after = File.stat(checklist_path).ino

    assert_equal ino_before, ino_after
  end

  # --- read_locked --------------------------------------------------------------------

  def test_read_locked_returns_exact_bytes
    append_checklist_line(:pending, "b7137962", "plastic", "First item")
    assert_equal File.read(checklist_path), SessionLedger.read_locked(checklist_path)
  end

  def test_read_locked_returns_empty_string_for_missing_path
    assert_equal "", SessionLedger.read_locked(File.join(@store, "nope.md"))
  end

  # --- open_day create -----------------------------------------------------------------

  def test_open_day_create_yields_exactly_one_entry
    result = SessionLedger.open_day(store: @store, day: @day, templates: TEMPLATES, author: "tester")

    assert result[:created]
    entries = Dir.children(result[:dir])
    assert_equal ["#{@day}.md"], entries
  end

  def test_open_day_create_writes_no_checklist_or_savepoint_or_actions_or_resources
    result = SessionLedger.open_day(store: @store, day: @day, templates: TEMPLATES, author: "tester")
    entries = Dir.children(result[:dir])

    refute_includes entries, "checklist.md"
    refute_includes entries, "savepoint.md"
    refute_includes entries, "actions"
    refute_includes entries, "resources"
  end

  # --- open_day validation ---------------------------------------------------------------

  def test_open_day_output_passes_intent_validator
    result = SessionLedger.open_day(store: @store, day: @day, templates: TEMPLATES, author: "tester")
    validation = IntentValidator.validate(result[:dir])

    assert validation[:ok], validation[:errors].join(", ")
    assert_empty validation[:errors]
  end

  def test_open_day_frontmatter_carries_mode_direct
    result = SessionLedger.open_day(store: @store, day: @day, templates: TEMPLATES, author: "tester")
    fm = IntentValidator.parse_frontmatter(SessionLedger.day_file(@store, @day))

    assert_equal "direct", fm["mode"]
    validation = IntentValidator.validate(result[:dir])
    assert validation[:ok]
  end

  def test_open_day_links_section_carries_empty_comment_verbatim
    SessionLedger.open_day(store: @store, day: @day, templates: TEMPLATES, author: "tester")
    content = File.read(SessionLedger.day_file(@store, @day))

    assert_includes content, LinksProjection::EMPTY_COMMENT
  end

  def test_open_day_body_has_no_notes_heading
    SessionLedger.open_day(store: @store, day: @day, templates: TEMPLATES, author: "tester")
    content = File.read(SessionLedger.day_file(@store, @day))

    refute_match(/^## Notes/, content)
  end

  # --- open_day join -----------------------------------------------------------------------

  def test_open_day_second_call_joins_with_zero_bytes_changed
    SessionLedger.open_day(store: @store, day: @day, templates: TEMPLATES, author: "tester")
    before_snapshot = snapshot_dir(SessionLedger.day_dir(@store, @day))

    result = SessionLedger.open_day(store: @store, day: @day, templates: TEMPLATES, author: "tester")
    after_snapshot = snapshot_dir(SessionLedger.day_dir(@store, @day))

    refute result[:created]
    assert_equal before_snapshot, after_snapshot
  end

  def snapshot_dir(dir)
    Dir.glob(File.join(dir, "**", "*")).select { |f| File.file?(f) }.sort.to_h do |f|
      [f, [File.mtime(f), File.binread(f)]]
    end
  end

  # --- open_day repair -------------------------------------------------------------------------

  def test_open_day_repairs_a_missing_day_file
    SessionLedger.open_day(store: @store, day: @day, templates: TEMPLATES, author: "tester")
    File.delete(SessionLedger.day_file(@store, @day))

    result = SessionLedger.open_day(store: @store, day: @day, templates: TEMPLATES, author: "tester")

    assert result[:created]
    assert File.exist?(SessionLedger.day_file(@store, @day))
  end

  # --- no environment read in the library --------------------------------------------------------

  def test_library_source_has_no_env_or_eval_token
    source = File.read(LIB_PATH)
    refute_match(/\bENV\b/, source)
    refute_match(/\beval\b/, source)
  end

  # --- the D13 API surface --------------------------------------------------------------------------

  def test_api_surface_matches_spec_d13
    %i[
      day_id valid_day_id? short_session_id project_slug
      sessions_root day_dir day_file checklist_path savepoint_path
      tmp_root session_tmp_dir pointer_path heartbeat_path ensure_tmp_root
      open_day
      sanitize_summary checklist_line savepoint_line parse_checklist_line
      append_line set_state read_locked
    ].each do |method_name|
      assert SessionLedger.respond_to?(method_name), "SessionLedger does not respond to #{method_name}"
    end
  end

  def test_all_d13_constants_are_defined
    assert_equal ".sessions", SessionLedger::SESSIONS_DIR
    assert_equal ".tmp", SessionLedger::TMP_DIR
    assert_equal(/\A\d{8}\z/, SessionLedger::DAY_ID)
    assert_equal %w[Item Done Note], SessionLedger::EVENTS
    assert_equal({ pending: "~", open: " ", done: "x" }, SessionLedger::STATES)
  end
end
