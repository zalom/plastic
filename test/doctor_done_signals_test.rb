# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/lock"

# Intent 93 - the done_signals doctor check reconciles the three done-signals
# (INDEX is canonical, outcome.md is the deliverable-exists signal, savepoint is
# the audit echo) and surfaces a stalled completion (terminal in INDEX but the
# End tail never released the delivery lock). Read-only, dependency-light: INDEX
# parsing + file presence + placeholder sentinel + Lock.fresh?. Hermetic temp
# homes, no eval, no ENV/global-constant seam.
class DoctorDoneSignalsTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-done-signals")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def global_store = File.join(@home, "store")

  def doctor = Doctor.new(plastic_home: @home)

  def check(name)
    doctor.check_done_signals.find { |c| c[:name] == name }
  end

  # Write a global INDEX.md placing intent `id` under `section`.
  def write_index(id, section:)
    body = +"# Index\n\n"
    ["Active", "Future", "Clusters", "Abandoned", "Completed"].each do |s|
      body << "## #{s}\n"
      body << "- [#{id} — t](store/#{id}--slug/#{id}--slug.md) — t\n" if s == section
      body << "\n"
    end
    File.write(File.join(@home, "INDEX.md"), body)
  end

  def intent_dir(id) = File.join(global_store, "#{id}--slug")

  def write_intent_dir(id)
    dir = intent_dir(id)
    FileUtils.mkdir_p(dir)
    dir
  end

  def write_outcome(id, disposition: "delivered")
    File.write(File.join(intent_dir(id), "outcome.md"),
               "---\ndisposition: #{disposition}\n---\n# Outcome: t\n\n## Summary\nok\n")
  end

  def write_placeholder_outcome(id)
    File.write(File.join(intent_dir(id), "outcome.md"),
               "#{Bridge::PLACEHOLDER_SENTINEL}\n")
  end

  def write_savepoint_done(id, disposition: "delivered")
    File.write(File.join(intent_dir(id), "savepoint.md"),
               "2026-07-03T00:00:00Z  Done  #{disposition}\n")
  end

  # A clean terminal intent: real outcome.md, Done savepoint, no lock.
  def test_pass_when_terminal_intent_is_fully_reconciled
    write_index("11", section: "Completed")
    write_intent_dir("11")
    write_outcome("11")
    write_savepoint_done("11")

    assert_equal "pass", check("signals_agree")[:status]
    assert_equal "pass", check("signals_complete")[:status]
    assert_equal "pass", check("stalled_completion")[:status]
  end

  # outcome.md is real but the intent is still Active -> HARD conflict (fail).
  # This is the one canonical INDEX-wins disagreement that must never persist.
  def test_conflict_when_outcome_real_but_still_active
    write_index("12", section: "Active")
    write_intent_dir("12")
    write_outcome("12")

    agree = check("signals_agree")
    assert_equal "fail", agree[:status]
    assert agree[:fix_hint], "expected a fix_hint on the conflict"
    assert(agree[:details].any? { |d| d.include?("still under ## Active") })
    # The completeness bucket does not fire on this state.
    assert_equal "pass", check("signals_complete")[:status]
  end

  # Terminal but outcome.md is still a placeholder -> completeness gap (WARN,
  # not fail): legacy terminal intents are immutable, so this stays advisory.
  def test_gap_when_terminal_but_outcome_placeholder
    write_index("13", section: "Abandoned")
    write_intent_dir("13")
    write_placeholder_outcome("13")
    write_savepoint_done("13", disposition: "abandoned")

    assert_equal "pass", check("signals_agree")[:status], "not a hard conflict"
    complete = check("signals_complete")
    assert_equal "warn", complete[:status]
    assert complete[:fix_hint]
    assert(complete[:details].any? { |d| d.include?("still a placeholder") })
  end

  # Terminal but outcome.md is missing entirely -> completeness gap (WARN).
  def test_gap_when_terminal_but_outcome_missing
    write_index("14", section: "Completed")
    write_intent_dir("14")
    write_savepoint_done("14")

    assert_equal "pass", check("signals_agree")[:status]
    complete = check("signals_complete")
    assert_equal "warn", complete[:status]
    assert(complete[:details].any? { |d| d.include?("missing") })
  end

  # Terminal with a real outcome.md but NO Done savepoint echo -> completeness
  # gap (WARN), never a hard fail.
  def test_gap_when_terminal_but_savepoint_echo_missing
    write_index("17", section: "Completed")
    write_intent_dir("17")
    write_outcome("17")
    File.write(File.join(intent_dir("17"), "savepoint.md"),
               "2026-07-03T00:00:00Z  Exec  started\n")

    assert_equal "pass", check("signals_agree")[:status]
    complete = check("signals_complete")
    assert_equal "warn", complete[:status]
    assert(complete[:details].any? { |d| d.include?("audit echo missing") })
  end

  # Terminal but the delivery.lock is still present -> stalled completion (warn).
  def test_stalled_completion_when_delivery_lock_present
    write_index("15", section: "Completed")
    write_intent_dir("15")
    write_outcome("15")
    write_savepoint_done("15")
    File.write(Lock.path(intent_dir("15")),
               '{"owner_session":"s","pid":1,"host":"h"}')

    agree = check("signals_agree")
    stalled = check("stalled_completion")
    assert_equal "pass", agree[:status], "signals themselves agree"
    assert_equal "warn", stalled[:status]
    assert stalled[:fix_hint], "expected a fix_hint on the stalled completion"
    refute(stalled[:fix_hint].downcase.include?("reactivation of a done intent") &&
           !stalled[:fix_hint].include?("NOT"),
           "fix_hint must say finishing a completion is NOT a reactivation")
  end

  # A stale delivery.lock at a terminal intent is reported as STALE.
  def test_stalled_completion_reports_stale_lock
    write_index("16", section: "Completed")
    write_intent_dir("16")
    write_outcome("16")
    write_savepoint_done("16")
    lock = Lock.path(intent_dir("16"))
    File.write(lock, '{"owner_session":"s","pid":1,"host":"h"}')
    old = Time.now - (Lock::TTL_SECONDS + 3600)
    File.utime(old, old, lock)

    stalled = check("stalled_completion")
    assert_equal "warn", stalled[:status]
    assert(stalled[:details].any? { |d| d.include?("STALE") })
  end

  # --- savepoint_truthful (intent 134) ----------------------------------------

  # A fully clean terminal intent's savepoint carries no phantom lines.
  def test_savepoint_truthful_passes_on_clean_terminal_intent
    write_index("20", section: "Completed")
    write_intent_dir("20")
    write_outcome("20")
    write_savepoint_done("20")

    assert_equal "pass", check("savepoint_truthful")[:status]
  end

  # A phantom on a LIVE (Active) intent is a warn, never a fail, with a fix_hint.
  def test_savepoint_truthful_warns_never_fails_on_live_phantom
    write_index("21", section: "Active")
    dir = write_intent_dir("21")
    File.write(File.join(dir, "savepoint.md"), "2026-07-03T00:00:00Z  How  plan.md created\n")

    result = check("savepoint_truthful")
    assert_equal "warn", result[:status]
    refute_equal "fail", result[:status]
    assert result[:fix_hint]
    assert(result[:details].any? { |d| d.include?("21") })
  end

  # A phantom on a TERMINAL intent is reported, not rewritten: doctor is read-only by
  # construction, so the savepoint file is byte-identical before and after the check runs, and
  # the detail names it report-only (immutable history), not auto-rebuildable.
  def test_savepoint_truthful_reports_terminal_phantom_without_rewriting
    write_index("22", section: "Completed")
    dir = write_intent_dir("22")
    write_outcome("22")
    savepoint_path = File.join(dir, "savepoint.md")
    File.write(savepoint_path,
               "2026-07-03T00:00:00Z  Done  delivered\n2026-07-03T00:05:00Z  Done  delivered\n")
    before = File.read(savepoint_path)

    result = check("savepoint_truthful")
    assert_equal "warn", result[:status]
    assert(result[:details].any? { |d| d.include?("22") && d.include?("report-only") })

    doctor.check_done_signals # run again to double-confirm no mutation
    assert_equal before, File.read(savepoint_path)
  end
end
