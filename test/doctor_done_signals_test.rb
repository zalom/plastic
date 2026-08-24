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
#
# Intent 211: replaces the frozen 170a id-list amnesty with a generic,
# runtime-computed repairability predicate. signals_complete narrows to the
# outcome.md delivery-claim bucket (always status "pass", informational); a
# new savepoint_operational check takes the operational bucket (missing
# savepoint.md, or missing its Done echo), warn+fixable, routed to
# maintenance-run --tool rebuild-savepoint.
#
# Intent 274: a per-store doctor-exclusions file, read via DoctorExclusions and keyed on
# (intent_id, rule), lets an operational-gap finding that can never legitimately close
# (219 D6 forbids inventing a disposition) leave the details list entirely. The count stays
# honest: doctor always reports how many findings were suppressed and where the file lives.
class DoctorDoneSignalsTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-done-signals")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def global_store = File.join(@home, "store")

  def doctor = Doctor.new(plastic_home: @home)

  def check(name) = doctor.check_done_signals.find { |c| c[:name] == name }

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

  # The global store's doctor-exclusions file, sibling to INDEX.md (intent 274, spec D6).
  def write_exclusions(text)
    File.write(File.join(@home, "doctor-exclusions"), text)
  end

  # write_index (above) writes exactly one id per call, overwriting the whole file - fine for
  # every existing single-id test. The precision-pin case (274) needs two ids in the SAME
  # section of the SAME INDEX.md, so this variant lists every id in `ids`.
  def write_index_multi(ids, section:)
    body = +"# Index\n\n"
    ["Active", "Future", "Clusters", "Abandoned", "Completed"].each do |s|
      body << "## #{s}\n"
      ids.each { |id| body << "- [#{id} — t](store/#{id}--slug/#{id}--slug.md) — t\n" } if s == section
      body << "\n"
    end
    File.write(File.join(@home, "INDEX.md"), body)
  end

  # A clean terminal intent: real outcome.md, Done savepoint, no lock.
  def test_pass_when_terminal_intent_is_fully_reconciled
    write_index("11", section: "Completed")
    write_intent_dir("11")
    write_outcome("11")
    write_savepoint_done("11")

    assert_equal "pass", check("signals_agree")[:status]
    assert_equal "pass", check("signals_complete")[:status]
    assert_equal "pass", check("savepoint_operational")[:status]
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

  # Terminal but outcome.md is still a placeholder -> a delivery-claim gap.
  # Never fabricated, so signals_complete stays "pass" (informational only).
  def test_legacy_note_when_terminal_but_outcome_placeholder
    write_index("13", section: "Abandoned")
    write_intent_dir("13")
    write_placeholder_outcome("13")
    write_savepoint_done("13", disposition: "abandoned")

    assert_equal "pass", check("signals_agree")[:status], "not a hard conflict"
    complete = check("signals_complete")
    assert_equal "pass", complete[:status], "outcome-missing is informational only, never warn"
    refute complete[:fixable], "there is no legitimate fix for a delivery-claim gap"
    assert(complete[:details].any? { |d| d.include?("still a placeholder") })
  end

  # Terminal but outcome.md is missing entirely -> same delivery-claim bucket.
  def test_legacy_note_when_terminal_but_outcome_missing
    write_index("14", section: "Completed")
    write_intent_dir("14")
    write_savepoint_done("14")

    assert_equal "pass", check("signals_agree")[:status]
    complete = check("signals_complete")
    assert_equal "pass", complete[:status]
    assert(complete[:details].any? { |d| d.include?("missing") })
  end

  # Terminal with a real outcome.md but NO Done savepoint echo -> operational
  # gap (WARN, fixable), while signals_complete stays clean (no outcome gap here).
  def test_operational_gap_when_terminal_but_savepoint_echo_missing
    write_index("17", section: "Completed")
    write_intent_dir("17")
    write_outcome("17")
    File.write(File.join(intent_dir("17"), "savepoint.md"),
               "2026-07-03T00:00:00Z  Exec  started\n")

    assert_equal "pass", check("signals_agree")[:status]
    assert_equal "pass", check("signals_complete")[:status], "no outcome gap here"
    operational = check("savepoint_operational")
    assert_equal "warn", operational[:status]
    assert operational[:fixable]
    assert_includes operational[:fix_hint], "rebuild-savepoint"
    assert(operational[:details].any? { |d| d.include?("no `Done delivered|abandoned` line") })
  end

  # Terminal with a real outcome.md but savepoint.md missing entirely (a case never
  # checked before 211) -> operational gap (WARN, fixable).
  def test_operational_gap_when_terminal_but_savepoint_missing_entirely
    write_index("18", section: "Completed")
    dir = write_intent_dir("18")
    write_outcome("18")
    refute File.exist?(File.join(dir, "savepoint.md"))

    operational = check("savepoint_operational")
    assert_equal "warn", operational[:status]
    assert(operational[:details].any? { |d| d.include?("missing entirely") })
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

  # Intent 211: the frozen 170a amnesty is gone outright. A terminal phantom line always
  # warns, unconditionally - no (scope, id) can suppress it anymore.
  def test_savepoint_truthful_never_suppresses_terminal_phantom
    write_index("23", section: "Completed")
    dir = write_intent_dir("23")
    write_outcome("23")
    File.write(File.join(dir, "savepoint.md"),
               "2026-07-03T00:00:00Z  Why  spec.md created\n2026-07-03T00:01:00Z  Why  spec.md created\n")

    # No amnesty mechanism exists anymore: every terminal phantom warns, unconditionally.
    assert_equal "warn", check("savepoint_truthful")[:status]
  end

  # Intent 211: the generic operational-gap predicate warns for ANY terminal intent missing
  # the Done bookend, with no allowlist axis left to consult (170a's amnesty is fully removed).
  # Intent 274 reopens a per-store, per-pair suppression axis (doctor-exclusions), but it is
  # opt-in and explicit: an intent not named in that file still warns.
  def test_savepoint_operational_warns_for_any_terminal_missing_echo
    write_index("30", section: "Completed")
    write_intent_dir("30")
    write_outcome("30")
    File.write(File.join(intent_dir("30"), "savepoint.md"),
               "2026-07-03T00:00:00Z  Exec  started\n")

    operational = check("savepoint_operational")
    assert_equal "warn", operational[:status], "no exclusion is registered for 30, so it still warns"
  end

  # Regression pin for the intent 222 extraction (done_signal_findings_for_dir): a terminal
  # dir missing BOTH outcome.md and the savepoint audit echo fires both gap classes
  # independently (never elsif), landing in the two SEPARATE buckets intent 211 introduced:
  # the outcome.md gap in signals_complete's (pass, informational) details, and the missing
  # Done echo in savepoint_operational's (warn, fixable) details.
  def test_extraction_preserves_both_gaps_when_a_dir_has_outcome_and_echo_gaps_together
    write_index("33", section: "Completed")
    write_intent_dir("33")
    File.write(File.join(intent_dir("33"), "savepoint.md"),
               "2026-07-03T00:00:00Z  Exec  started\n")

    complete = check("signals_complete")
    operational = check("savepoint_operational")
    assert_equal "pass", complete[:status]
    assert_equal "warn", operational[:status]
    assert(complete[:details].any? { |d| d.include?("33") && d.include?("outcome.md is missing") })
    assert(operational[:details].any? { |d| d.include?("33") && d.include?("no `Done delivered|abandoned` line") })
  end

  # --- doctor-exclusions (intent 274) ---------------------------------------------------

  # An intent registered under savepoint_operational leaves the details list entirely and the
  # check reaches "pass"; the count stays honest in the message.
  def test_excluded_pair_clears_the_warning
    write_index("40", section: "Completed")
    write_intent_dir("40")
    write_outcome("40")
    write_exclusions("savepoint_operational 40\n")

    operational = check("savepoint_operational")
    assert_equal "pass", operational[:status]
    assert_empty operational[:details]
    assert_includes operational[:message], "1 excluded"
  end

  # PRECISION PIN (the 32-style regression): two terminal intents both missing their savepoint,
  # only one is registered. The check stays warn, details name only the unregistered id, and
  # the message reports exactly one exclusion.
  def test_precision_pin_only_the_registered_id_is_suppressed
    write_index_multi(["41", "42"], section: "Completed")
    write_intent_dir("41")
    write_outcome("41")
    write_intent_dir("42")
    write_outcome("42")
    write_exclusions("savepoint_operational 41\n")

    operational = check("savepoint_operational")
    assert_equal "warn", operational[:status]
    refute(operational[:details].any? { |d| d.include?("41") }, "the registered id must not appear in details")
    assert(operational[:details].any? { |d| d.include?("42") }, "the unregistered id must still appear")
    assert_includes operational[:message], "1 excluded"
  end

  # PER-PAIR PRECISION: the key is (intent_id, rule), never bare intent_id. An intent
  # registered under savepoint_operational and missing BOTH outcome.md and savepoint.md still
  # shows up in signals_complete (which never consults the exclusion file).
  def test_exclusion_is_per_pair_not_per_intent
    write_index("43", section: "Completed")
    write_intent_dir("43")
    write_exclusions("savepoint_operational 43\n")

    assert_equal "pass", check("savepoint_operational")[:status]
    complete = check("signals_complete")
    assert(complete[:details].any? { |d| d.include?("43") }, "signals_complete must still report 43")
  end

  # LOUD LOADER (spec D5): a malformed exclusion file forces a warn even when there are zero
  # real operational gaps in the store, with the loader error surfaced in details.
  def test_malformed_exclusions_file_forces_warn_with_zero_real_gaps
    write_index("44", section: "Completed")
    write_intent_dir("44")
    write_outcome("44")
    write_savepoint_done("44")
    write_exclusions("not_a_real_rule 44\n")

    operational = check("savepoint_operational")
    assert_equal "warn", operational[:status]
    assert(operational[:details].any? { |d| d.include?("unknown or non-excludable rule") })
  end

  # Review F1 regression: a doctor-exclusions file carrying a byte invalid in its declared
  # encoding must not crash the whole doctor run - check_done_signals must still return a
  # result (loud warn via the loader error, per D5), never raise.
  def test_invalid_byte_in_exclusions_file_does_not_crash_doctor
    write_index("46", section: "Completed")
    write_intent_dir("46")
    write_outcome("46")
    write_savepoint_done("46")
    File.binwrite(File.join(@home, "doctor-exclusions"), "# bad byte caf\xE9\nsavepoint_operational 46\n")

    operational = check("savepoint_operational")
    assert_equal "pass", operational[:status]
  end

  # FAIL-OPEN (spec D5): no exclusion file at all leaves behavior identical to before intent 274.
  def test_no_exclusions_file_is_byte_identical_to_before
    write_index("45", section: "Completed")
    write_intent_dir("45")
    write_outcome("45")

    operational = check("savepoint_operational")
    assert_equal "warn", operational[:status]
    refute_includes operational[:message], "excluded"
    assert(operational[:details].any? { |d| d.include?("45") })
  end

  # --- dead exclusion rows (intent 280) -------------------------------------------------

  # FALSIFIABILITY (208): a terminal intent with a real outcome.md AND a Done savepoint,
  # registered under savepoint_operational, suppresses nothing this run - the row is dead.
  # Reported informationally in the details AND the message, status stays "pass".
  def test_dead_exclusion_row_is_reported_when_the_gap_is_gone
    write_index("50", section: "Completed")
    write_intent_dir("50")
    write_outcome("50")
    write_savepoint_done("50")
    write_exclusions("savepoint_operational 50\n")

    operational = check("savepoint_operational")
    assert_equal "pass", operational[:status]
    assert_includes operational[:message], "1 dead row"
    assert(operational[:details].any? { |d| d.include?("50") && d.include?(File.join(@home, "doctor-exclusions")) })
  end

  # A registered id that matches no walked intent directory at all reports distinct wording
  # from case 6 above ("no current ... finding" vs "no live intent directory").
  def test_dead_exclusion_row_for_an_unknown_id_reports_no_live_intent
    write_index("51", section: "Completed")
    write_intent_dir("51")
    write_outcome("51")
    write_savepoint_done("51")
    write_exclusions("savepoint_operational 999\n")

    operational = check("savepoint_operational")
    assert(operational[:details].any? { |d| d.include?("999") && d.include?("no live intent directory") })
    refute(operational[:details].any? { |d| d.include?("999") && d.include?("no current") })
  end

  # FALSE-POSITIVE GUARD: two terminal intents both missing their savepoint entirely, only one
  # registered. The registered id is a LIVE exclusion (it still suppresses a real gap) and must
  # never be reported as a dead row.
  def test_a_live_exclusion_row_is_never_reported_dead
    write_index_multi(["52", "53"], section: "Completed")
    write_intent_dir("52")
    write_outcome("52")
    write_intent_dir("53")
    write_outcome("53")
    write_exclusions("savepoint_operational 52\n")

    operational = check("savepoint_operational")
    assert_includes operational[:message], "1 excluded"
    refute_includes operational[:message], "dead row"
    refute(operational[:details].any? { |d| d.include?("52") && d.include?("dead row") })
  end

  # Dead rows are informational only: status stays "pass" exactly as it would with zero dead
  # rows, because the gap they name is truly gone.
  def test_dead_rows_do_not_change_the_check_status
    write_index("54", section: "Completed")
    write_intent_dir("54")
    write_outcome("54")
    write_savepoint_done("54")
    write_exclusions("savepoint_operational 54\n")

    operational = check("savepoint_operational")
    assert_equal "pass", operational[:status]
    assert_includes operational[:message], "No terminal intent is missing an operational savepoint.md or its Done echo"
  end

  # A dead row and a real, unregistered remaining gap coexist in the same run: status stays
  # "warn" (the real gap governs status), and both counts are reported, separately and correctly.
  def test_dead_rows_are_reported_alongside_remaining_gaps
    write_index_multi(["55", "56"], section: "Completed")
    write_intent_dir("55")
    write_outcome("55")
    write_savepoint_done("55") # registered but fully clean - the dead row
    write_intent_dir("56")
    write_outcome("56") # savepoint.md missing entirely, never registered - the real gap
    write_exclusions("savepoint_operational 55\n")

    operational = check("savepoint_operational")
    assert_equal "warn", operational[:status]
    assert_includes operational[:message], "1 terminal intent"
    assert_includes operational[:message], "1 dead row"
    assert(operational[:details].any? { |d| d.include?("55") && d.include?("no current") })
    assert(operational[:details].any? { |d| d.include?("56") && d.include?("missing entirely") })
  end

  # With zero dead rows the message and the exclusion count are unchanged (D8's precedent
  # restated for the dead-row axis).
  def test_no_dead_rows_leaves_the_message_unchanged
    write_index("57", section: "Completed")
    write_intent_dir("57")
    write_outcome("57")
    write_exclusions("savepoint_operational 57\n")

    operational = check("savepoint_operational")
    assert_equal "pass", operational[:status]
    refute_includes operational[:message], "dead row"
    assert_includes operational[:message], "1 excluded"
  end

  # REGRESSION (post-review fix item 1): "59--ghost" has a REAL directory on disk but is never
  # referenced anywhere in INDEX.md - a de-indexed "ghost". The buggy v1 predicate derived
  # known_ids from walk membership alone, so this id's directory being real did not matter: it
  # was never visited by the walk, and its registered row was misclassified :no_intent ("a typo,
  # or the intent was deleted") even though the directory plainly still existed. The fix resolves
  # known_ids against a direct scan of the store's own directory listing, and additionally
  # leaves an unevaluated-but-known id out of the dead-row report entirely (no evidence either
  # way) - so doctor must never call "59" dead, under either reason.
  def test_ghost_directory_absent_from_index_is_never_reported_as_a_dead_row
    write_index("58", section: "Completed")
    write_intent_dir("58")
    write_outcome("58")
    write_savepoint_done("58") # a genuinely repaired gap - the flagship falsifiability case (6)
    FileUtils.mkdir_p(File.join(global_store, "59--ghost"))
    write_exclusions("savepoint_operational 58 59\n")

    operational = check("savepoint_operational")
    assert_equal "pass", operational[:status]
    # Matches the exact "rule id" substring the detail-line format produces (`"#{rule} #{id} -
    # #{reason}"`), not a bare "59" - a random tmpdir suffix from Dir.mktmpdir can otherwise
    # spuriously contain that digit sequence and make this assertion flaky.
    refute(operational[:details].any? { |d| d.include?("savepoint_operational 59") },
      "a real, on-disk directory absent from INDEX carries no evidence and must never be called dead")
    assert(operational[:details].any? { |d| d.include?("savepoint_operational 58") && d.include?("no current") },
      "the genuinely repaired id (58) must still be reported dead, with the :no_finding wording")
    assert_includes operational[:message], "1 dead row"
  end
end
