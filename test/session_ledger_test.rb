# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../scripts/lib/session_ledger"

# Intent 297, task 1: the pure half of SessionLedger - identity, day paths,
# session paths, line building and parsing, constants. No process spawning:
# this file only requires the library in process, so it reads no ambient
# PLASTIC_HOME or session id itself, and needs no PLASTIC_TMP isolation.
class SessionLedgerTest < Minitest::Test
  LIB_PATH = File.expand_path("../scripts/lib/session_ledger.rb", __dir__)

  def setup
    @store = Dir.mktmpdir("session-ledger")
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  # --- day_id ---------------------------------------------------------------

  def test_day_id_returns_eight_digits_for_the_injected_local_time
    now = Time.new(2026, 8, 29, 23, 0, 0)
    assert_equal "20260829", SessionLedger.day_id(now)
  end

  def test_day_id_matches_time_now_strftime
    assert_equal Time.now.strftime("%Y%m%d"), SessionLedger.day_id
  end

  def test_day_id_body_never_calls_utc
    source = File.read(LIB_PATH)
    body = source[/def day_id.*?\n  end\n/m]
    refute_nil body, "could not locate the day_id method body"
    refute_match(/\.utc\b/, body, "day_id must never call .utc")
  end

  # --- valid_day_id? ---------------------------------------------------------

  def test_valid_day_id_accepts_well_formed_dates
    assert SessionLedger.valid_day_id?("20260829")
  end

  def test_valid_day_id_rejects_malformed_shapes
    refute SessionLedger.valid_day_id?("2026-08-29")
    refute SessionLedger.valid_day_id?("2026082")
    refute SessionLedger.valid_day_id?("202608299")
    refute SessionLedger.valid_day_id?("abcdefgh")
  end

  def test_valid_day_id_rejects_a_shape_match_that_is_not_a_real_date
    refute SessionLedger.valid_day_id?("20261340")
  end

  # --- short_session_id -------------------------------------------------------

  def test_short_session_id_downcases_and_truncates_a_uuid
    assert_equal "b7137962", SessionLedger.short_session_id("B7137962-3F4A-4B11-9C22-000000000000")
  end

  def test_short_session_id_prefers_explicit_over_env
    assert_equal "explicit", SessionLedger.short_session_id("explicit-id", "env-id")[0, 8]
  end

  def test_short_session_id_uses_env_when_explicit_is_nil_or_blank
    assert_equal "envid123", SessionLedger.short_session_id(nil, "envid123456")
    assert_equal "envid123", SessionLedger.short_session_id("   ", "envid123456")
  end

  def test_short_session_id_falls_back_to_local_when_both_blank
    assert_equal "local", SessionLedger.short_session_id(nil, nil)
    assert_equal "local", SessionLedger.short_session_id("", "  ")
  end

  def test_short_session_id_drops_characters_outside_alnum_before_slicing
    assert_equal "ab12", SessionLedger.short_session_id("a-b_1!2")
  end

  # --- project_slug -----------------------------------------------------------

  def write_projects_yml(home, projects)
    FileUtils.mkdir_p(home)
    File.write(File.join(home, "projects.yml"), YAML.dump("projects" => projects))
  end

  def test_project_slug_prefers_the_longest_matching_path
    home = File.join(@store, "home")
    outer = File.join(@store, "outer")
    inner = File.join(outer, "inner")
    FileUtils.mkdir_p(inner)
    write_projects_yml(home, {
      "outer-project" => { "path" => outer },
      "inner-project" => { "path" => inner },
    })

    assert_equal "inner-project", SessionLedger.project_slug(File.join(inner, "sub"), plastic_home: home)
  end

  def test_project_slug_matches_the_outer_path_when_cwd_is_only_inside_it
    home = File.join(@store, "home2")
    outer = File.join(@store, "outer2")
    inner = File.join(outer, "inner2")
    FileUtils.mkdir_p(inner)
    write_projects_yml(home, {
      "outer-project" => { "path" => outer },
      "inner-project" => { "path" => inner },
    })

    cwd = File.join(outer, "elsewhere")
    FileUtils.mkdir_p(cwd)
    assert_equal "outer-project", SessionLedger.project_slug(cwd, plastic_home: home)
  end

  def test_project_slug_falls_back_to_global_when_no_path_matches
    home = File.join(@store, "home3")
    write_projects_yml(home, { "some-project" => { "path" => File.join(@store, "elsewhere") } })

    cwd = File.join(@store, "unrelated")
    FileUtils.mkdir_p(cwd)
    result = SessionLedger.project_slug(cwd, plastic_home: home)

    assert_equal "global", result
    refute_equal File.basename(cwd), result
  end

  def test_project_slug_falls_back_to_global_when_projects_yml_is_missing
    home = File.join(@store, "home4")
    FileUtils.mkdir_p(home)

    assert_equal "global", SessionLedger.project_slug(@store, plastic_home: home)
  end

  def test_project_slug_skips_a_matching_but_invalid_slug_and_falls_back_to_global
    home = File.join(@store, "home5")
    outer = File.join(@store, "outer5")
    FileUtils.mkdir_p(outer)
    write_projects_yml(home, { "Not_A-Valid Slug" => { "path" => outer } })

    assert_equal "global", SessionLedger.project_slug(outer, plastic_home: home)
  end

  def test_project_slug_matches_the_next_best_valid_slug_when_the_longer_match_is_invalid
    home = File.join(@store, "home6")
    outer = File.join(@store, "outer6")
    inner = File.join(outer, "inner6")
    FileUtils.mkdir_p(inner)
    write_projects_yml(home, {
      "outer-project" => { "path" => outer },
      "not valid" => { "path" => inner },
    })

    assert_equal "outer-project", SessionLedger.project_slug(File.join(inner, "sub"), plastic_home: home)
  end

  # --- day paths ---------------------------------------------------------------

  def test_day_path_helpers_return_exact_joins
    day = "20260829"
    assert_equal File.join(@store, ".sessions"), SessionLedger.sessions_root(@store)
    assert_equal File.join(@store, ".sessions", day), SessionLedger.day_dir(@store, day)
    assert_equal File.join(@store, ".sessions", day, "#{day}.md"), SessionLedger.day_file(@store, day)
    assert_equal File.join(@store, ".sessions", day, "checklist.md"), SessionLedger.checklist_path(@store, day)
    assert_equal File.join(@store, ".sessions", day, "savepoint.md"), SessionLedger.savepoint_path(@store, day)
  end

  # --- session paths -------------------------------------------------------------

  def test_session_path_helpers_return_exact_joins
    session_id = "b7137962"
    assert_equal File.join(@store, ".tmp"), SessionLedger.tmp_root(@store)
    assert_equal File.join(@store, ".tmp", session_id), SessionLedger.session_tmp_dir(@store, session_id)
    assert_equal File.join(@store, ".tmp", session_id, "current"), SessionLedger.pointer_path(@store, session_id)
    assert_equal File.join(@store, ".tmp", session_id, "heartbeat"), SessionLedger.heartbeat_path(@store, session_id)
  end

  def test_ensure_tmp_root_creates_the_directory_and_gitignore
    root = SessionLedger.ensure_tmp_root(@store)
    assert_equal File.join(@store, ".tmp"), root
    assert File.directory?(root)
    assert_equal "*\n", File.read(File.join(root, ".gitignore"))
  end

  def test_ensure_tmp_root_is_idempotent
    SessionLedger.ensure_tmp_root(@store)
    gitignore = File.join(@store, ".tmp", ".gitignore")
    File.write(gitignore, "custom\n")

    SessionLedger.ensure_tmp_root(@store)

    assert_equal "custom\n", File.read(gitignore)
  end

  # --- sanitize_summary -----------------------------------------------------------

  def test_sanitize_summary_collapses_whitespace_and_strips
    assert_equal "a b c", SessionLedger.sanitize_summary("  a\n\n b   \t c  ")
  end

  def test_sanitize_summary_caps_at_two_hundred_characters
    long = "a" * 300
    result = SessionLedger.sanitize_summary(long)
    assert_equal 200, result.length
    assert result.end_with?("...")
    assert_equal "#{"a" * 197}...", result
  end

  def test_sanitize_summary_returns_empty_string_for_whitespace_only_input
    assert_equal "", SessionLedger.sanitize_summary("   \n\t  ")
  end

  # --- checklist_line ---------------------------------------------------------------

  PENDING_EXAMPLE = "- [~] [b7137962] [plastic] Change how titles appear on the resume page\n"
  OPEN_EXAMPLE = "- [ ] [b7137962] [plastic] Change how titles appear on the resume page\n"
  DONE_EXAMPLE = "- [x] [b7137962] [plastic] Change how titles appear on the resume page\n"

  def test_checklist_line_matches_byte_exact_examples
    summary = "Change how titles appear on the resume page"
    assert_equal PENDING_EXAMPLE, SessionLedger.checklist_line(:pending, "b7137962", "plastic", summary)
    assert_equal OPEN_EXAMPLE, SessionLedger.checklist_line(:open, "b7137962", "plastic", summary)
    assert_equal DONE_EXAMPLE, SessionLedger.checklist_line(:done, "b7137962", "plastic", summary)
  end

  def test_checklist_line_markers_are_fixed_width
    assert_equal PENDING_EXAMPLE.length, OPEN_EXAMPLE.length
    assert_equal PENDING_EXAMPLE.length, DONE_EXAMPLE.length
  end

  def test_checklist_line_raises_on_unknown_state
    assert_raises(ArgumentError) { SessionLedger.checklist_line(:bogus, "s", "p", "summary") }
  end

  # --- savepoint_line -----------------------------------------------------------------

  def test_savepoint_line_matches_byte_exact_example
    now = Time.utc(2026, 8, 29, 13, 26, 52)
    line = SessionLedger.savepoint_line("Item", "b7137962", "plastic",
      "Change how titles appear on the resume page", now: now)

    expected = "2026-08-29T13:26:52Z  Item  [b7137962] [plastic] " \
      "Change how titles appear on the resume page\n"
    assert_equal expected, line
  end

  def test_savepoint_line_splits_into_three_parts_on_double_space
    now = Time.utc(2026, 8, 29, 13, 26, 52)
    line = SessionLedger.savepoint_line("Done", "b7137962", "plastic", "summary", now: now)
    parts = line.chomp.split(/\s{2,}/)
    assert_equal 3, parts.length
  end

  def test_savepoint_line_raises_on_unknown_event
    assert_raises(ArgumentError) do
      SessionLedger.savepoint_line("Bogus", "s", "p", "summary", now: Time.now)
    end
  end

  # --- parse_checklist_line ------------------------------------------------------------

  def test_parse_checklist_line_round_trips_each_state
    summary = "Change how titles appear on the resume page"
    [:pending, :open, :done].each do |state|
      line = SessionLedger.checklist_line(state, "b7137962", "plastic", summary)
      parsed = SessionLedger.parse_checklist_line(line)
      assert_equal({ state: state, session: "b7137962", project: "plastic", summary: summary }, parsed)
    end
  end

  def test_parse_checklist_line_keeps_a_bracket_typed_inside_the_summary
    summary = "Fix the [thing] that broke"
    line = SessionLedger.checklist_line(:pending, "b7137962", "plastic", summary)
    parsed = SessionLedger.parse_checklist_line(line)
    assert_equal summary, parsed[:summary]
  end

  def test_parse_checklist_line_returns_nil_for_a_non_matching_line
    assert_nil SessionLedger.parse_checklist_line("not a checklist line\n")
  end

  # --- constants ------------------------------------------------------------------------

  def test_constants_match_spec_d13_exactly
    assert_equal ".sessions", SessionLedger::SESSIONS_DIR
    assert_equal ".tmp", SessionLedger::TMP_DIR
    assert_equal(/\A\d{8}\z/, SessionLedger::DAY_ID)
    assert_equal %w[Item Done Note], SessionLedger::EVENTS
    assert_equal({ pending: "~", open: " ", done: "x", moved: ">", dropped: "-", promoted: "^" }, SessionLedger::STATES)
  end

  # --- capture_worthy? (spec D2, D7; supersedes 298 D2(c); matrix row A) ----------------
  #
  # A pure predicate deciding whether a prompt earns a pending checklist line. Bias is
  # ACCEPT: it rejects only on four named rules (10-char floor, whole-prompt harness
  # envelope, bare trigger, and a bare question/remark carrying no work marker).
  # Over-rejecting real work is worse than the bug this predicate fixes (D2).

  def test_a1_rejects_a_bare_question
    refute SessionLedger.capture_worthy?("what does the arm verb do to the worktree?")
  end

  def test_a2_rejects_a_whole_prompt_harness_envelope
    refute SessionLedger.capture_worthy?("<task-notification>a background job finished</task-notification>")
    refute SessionLedger.capture_worthy?("<system-reminder>some injected reminder text here</system-reminder>")
  end

  def test_a3_rejects_a_bare_remark
    refute SessionLedger.capture_worthy?("that release went smoother than the last one")
  end

  def test_a4_accepts_an_imperative_work_prompt
    assert SessionLedger.capture_worthy?("fix the dashboard date parser for the wikilink form")
  end

  def test_a5_accepts_a_work_shaped_question
    assert SessionLedger.capture_worthy?("can you fix the dashboard date parser?")
    assert SessionLedger.capture_worthy?("could you add a test for the wikilink form?")
  end

  def test_a6_accepts_an_envelope_followed_by_real_work
    prompt = "<system-reminder>ignore me</system-reminder>\nfix the dashboard date parser"
    assert SessionLedger.capture_worthy?(prompt)
  end

  def test_a7_rejects_a_bare_trigger_whole_prompt_only
    refute SessionLedger.capture_worthy?("continue")
    refute SessionLedger.capture_worthy?("auto")
    refute SessionLedger.capture_worthy?("  Continue  ")
    refute SessionLedger.capture_worthy?("AUTO")
    assert SessionLedger.capture_worthy?("continue the dashboard fix and then release")
  end

  def test_a8_keeps_the_ten_character_floor
    refute SessionLedger.capture_worthy?("fix it")
  end
end
