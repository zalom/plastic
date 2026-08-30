# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/doctor"
require_relative "../scripts/lib/session_ledger"

# Intent 308 - the session_ledger doctor category, store scope. Two checks: orphaned
# .tmp/<session>/ dirs whose heartbeat is missing or older than the TTL (warn, fixable,
# never deleted), and the shape of .sessions/ day ledgers (digits-only day ids that parse
# as dates, one <day>.md per day dir, nothing but directories). Hermetic tmp home; the
# clock is injected as `now:` and every fixture timestamp is derived from it, never a
# clock ahead of a file's mtime. Both checks live in the global store only (spec D7): a
# project scope emits no session_ledger check at all.
class DoctorSessionLedgerTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-session-ledger")
    FileUtils.mkdir_p(global_store)
    File.write(File.join(@home, "INDEX.md"), "# Index\n\n## Active\n\n## Future\n\n## Clusters\n\n## Abandoned\n\n## Completed\n")
    @now = Time.now
  end

  def teardown
    FileUtils.chmod_R(0o755, @home) if @home && Dir.exist?(@home)
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def global_store = File.join(@home, "store")

  def doctor = Doctor.new(plastic_home: @home)

  def checks = doctor.check_session_ledger(now: @now)

  def check(name) = checks.find { |c| c[:name] == name }

  # A .tmp/<session>/ dir. `heartbeat:` is nil (no file), a Time (ISO-8601 content), or a
  # String written verbatim. `mtime:` backdates the dir and the heartbeat file. `pointer:`
  # false skips writing `current` at all (row H's no-pointer class, spec D9).
  def write_session_tmp(session, heartbeat: @now, mtime: nil, pointer: true)
    SessionLedger.ensure_tmp_root(global_store)
    dir = SessionLedger.session_tmp_dir(global_store, session)
    FileUtils.mkdir_p(dir)
    File.write(SessionLedger.pointer_path(global_store, session), "20260830\n") if pointer
    unless heartbeat.nil?
      content = heartbeat.is_a?(Time) ? "#{heartbeat.utc.iso8601}\n" : heartbeat
      File.write(SessionLedger.heartbeat_path(global_store, session), content)
    end
    if mtime
      File.utime(mtime, mtime, SessionLedger.heartbeat_path(global_store, session)) unless heartbeat.nil?
      File.utime(mtime, mtime, dir)
    end
    dir
  end

  def write_day_dir(day, day_file: true, checklist: true)
    dir = SessionLedger.day_dir(global_store, day)
    FileUtils.mkdir_p(dir)
    File.write(SessionLedger.day_file(global_store, day), "---\nmode: direct\n---\n# Session #{day}\n") if day_file
    File.write(SessionLedger.checklist_path(global_store, day), "# Checklist\n") if checklist
    dir
  end

  # --- orphaned_session_tmp --------------------------------------------------------------

  def test_all_checks_pass_when_neither_directory_exists
    assert_equal %w[orphaned_session_tmp no_pointer_session_tmp day_ledger_shape], checks.map { |c| c[:name] }
    assert(checks.all? { |c| c[:status] == "pass" }, checks.inspect)
    assert(checks.all? { |c| c[:category] == "session_ledger" })
  end

  def test_fresh_heartbeat_is_a_live_session_and_passes
    write_session_tmp("abcd1234", heartbeat: @now - 3600)
    assert_equal "pass", check("orphaned_session_tmp")[:status]
  end

  def test_gitignore_alone_is_not_a_session
    SessionLedger.ensure_tmp_root(global_store)
    assert_equal "pass", check("orphaned_session_tmp")[:status]
  end

  def test_heartbeat_older_than_the_ttl_warns_with_the_dir_named
    old = @now - Doctor::ORPHAN_TTL_SECONDS - 60
    dir = write_session_tmp("dead0001", heartbeat: old)
    c = check("orphaned_session_tmp")

    assert_equal "warn", c[:status]
    assert c[:fixable]
    assert_equal 1, c[:details].size
    assert_includes c[:details].first, dir
    assert_includes c[:details].first, "dead0001"
    assert_match(/heartbeat/, c[:fix_hint])
    refute_match(/rm -rf/, c[:fix_hint])
    assert Dir.exist?(dir), "the check must never delete a directory"
  end

  def test_heartbeat_just_inside_the_ttl_passes
    write_session_tmp("edge0001", heartbeat: @now - Doctor::ORPHAN_TTL_SECONDS + 120)
    assert_equal "pass", check("orphaned_session_tmp")[:status]
  end

  def test_missing_heartbeat_falls_back_to_the_dir_mtime
    old = @now - Doctor::ORPHAN_TTL_SECONDS - 60
    write_session_tmp("nohb0001", heartbeat: nil, mtime: old)
    write_session_tmp("nohb0002", heartbeat: nil)
    c = check("orphaned_session_tmp")

    assert_equal "warn", c[:status]
    assert_equal 1, c[:details].size
    assert_includes c[:details].first, "nohb0001"
  end

  def test_garbage_heartbeat_falls_back_to_the_file_mtime
    old = @now - Doctor::ORPHAN_TTL_SECONDS - 60
    write_session_tmp("junk0001", heartbeat: "not a time\n", mtime: old)
    write_session_tmp("junk0002", heartbeat: "not a time\n")
    c = check("orphaned_session_tmp")

    assert_equal "warn", c[:status]
    assert_equal 1, c[:details].size
    assert_includes c[:details].first, "junk0001"
  end

  def test_a_file_under_tmp_root_is_ignored
    SessionLedger.ensure_tmp_root(global_store)
    File.write(File.join(SessionLedger.tmp_root(global_store), "stray"), "x")
    assert_equal "pass", check("orphaned_session_tmp")[:status]
  end

  # --- no_pointer_session_tmp (row H, spec D9) -----------------------------------------

  def test_h1_no_pointer_dir_under_the_short_ttl_passes
    write_session_tmp("nopt0001", heartbeat: @now - 60, pointer: false)
    assert_equal "pass", check("no_pointer_session_tmp")[:status]
  end

  def test_h2_no_pointer_dir_past_the_short_ttl_warns_distinctly_and_leaves_the_24h_check_alone
    old = @now - Doctor::NO_POINTER_TTL_SECONDS - 60
    dir = write_session_tmp("nopt0002", heartbeat: old, pointer: false)
    no_pointer_check = check("no_pointer_session_tmp")

    assert_equal "warn", no_pointer_check[:status]
    assert_equal 1, no_pointer_check[:details].size
    assert_includes no_pointer_check[:details].first, dir
    assert_includes no_pointer_check[:details].first, "nopt0002"
    refute_equal check("orphaned_session_tmp")[:message], no_pointer_check[:message]
    assert_equal "pass", check("orphaned_session_tmp")[:status],
                 "a no-pointer dir well under 24h old must not affect the 24-hour orphan count"
  end

  def test_h3_a_healthy_young_session_with_a_pointer_is_not_flagged
    write_session_tmp("live0001", heartbeat: @now)
    assert_equal "pass", check("no_pointer_session_tmp")[:status]
  end

  # --- day_ledger_shape ------------------------------------------------------------------

  def test_healthy_day_dirs_pass
    write_day_dir("20260828")
    write_day_dir("20260829", checklist: false)
    assert_equal "pass", check("day_ledger_shape")[:status]
  end

  def test_malformed_names_missing_day_file_and_stray_file_each_get_one_detail
    write_day_dir("20260828")
    write_day_dir("2026-08-29")
    write_day_dir("20261340")
    write_day_dir("20260827", day_file: false)
    File.write(File.join(SessionLedger.sessions_root(global_store), "notes.md"), "x")
    c = check("day_ledger_shape")

    assert_equal "warn", c[:status]
    assert c[:fixable]
    assert_equal 4, c[:details].size, c[:details].inspect
    assert(c[:details].any? { |d| d.include?("2026-08-29") && d.include?("not a YYYYMMDD") })
    assert(c[:details].any? { |d| d.include?("20261340") && d.include?("not a YYYYMMDD") })
    assert(c[:details].any? { |d| d.include?("20260827") && d.include?("20260827.md") })
    assert(c[:details].any? { |d| d.include?("notes.md") && d.include?("not a directory") })
    assert_match(/file-session-intent --day <day>/, c[:fix_hint])
  end

  def test_extra_markdown_beside_the_day_file_is_not_flagged
    dir = write_day_dir("20260828")
    %w[spec.md plan.md outcome.md].each { |f| File.write(File.join(dir, f), "# x\n") }
    assert_equal "pass", check("day_ledger_shape")[:status]
  end

  # --- scoping ------------------------------------------------------------------------------

  def test_project_scope_emits_no_session_ledger_check_and_global_scope_does
    project_store = File.join(@home, "projects", "demo", "store")
    FileUtils.mkdir_p(SessionLedger.day_dir(project_store, "bad-day"))
    File.write(File.join(@home, "projects", "demo", "INDEX.md"), "# Index\n")
    write_day_dir("bad-global-day")

    assert_empty doctor.check_session_ledger(now: @now, scopes: ["project:demo"])
    global = doctor.check_session_ledger(now: @now, scopes: ["global"]).find { |c| c[:name] == "day_ledger_shape" }
    assert_equal "warn", global[:status]
    assert_equal 1, global[:details].size, "only the global store's day dir is a finding"
    assert_includes global[:details].first, "bad-global-day"
  end

  def test_todays_open_day_passes
    write_day_dir(SessionLedger.day_id(@now))
    assert_equal "pass", check("day_ledger_shape")[:status]
  end

  def test_unreadable_tmp_root_fails_open
    write_session_tmp("dead0001", heartbeat: @now - Doctor::ORPHAN_TTL_SECONDS - 60)
    File.chmod(0o000, SessionLedger.tmp_root(global_store))
    begin
      c = check("orphaned_session_tmp")
      assert_equal "pass", c[:status], "an unreadable .tmp/ is skipped, never raised"
    ensure
      File.chmod(0o755, SessionLedger.tmp_root(global_store))
    end
  end

  def test_full_run_carries_the_session_ledger_category
    write_session_tmp("dead0001", heartbeat: @now - Doctor::ORPHAN_TTL_SECONDS - 60)
    result = doctor.run_checks("claude")
    assert_includes result[:checks].map { |c| c[:category] }, "session_ledger"
  end

  def test_store_scope_runs_carry_the_session_ledger_category
    write_session_tmp("dead0001", heartbeat: @now - Doctor::ORPHAN_TTL_SECONDS - 60)
    result = doctor.run_store_checks(:global, qmd_detector: -> { nil }, qmd_runner: ->(*) { nil })
    names = result[:checks].map { |c| c[:name] }
    assert_includes names, "orphaned_session_tmp"
    assert_includes names, "day_ledger_shape"
  end
end
