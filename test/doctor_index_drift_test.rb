# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"

# Doctor#check_done_signals (intent 337, n6): a new finding surfaces the
# IndexProjection drift - a real terminal ledger line (Done delivered or
# abandoned) that disagrees with the INDEX section an intent currently sits
# in. Emitted from the EXISTING check_done_signals (scripts/doctor.rb),
# never from scripts/lib/doctor_core.rb (the installation doctor, not
# touched by this intent). Scoped to what savepoint_operational does not
# already report (row 6.7): IndexProjection's own drift computation already
# excludes a silent or absent ledger (row 5.13), which is exactly what
# savepoint_operational covers, so no extra filtering is needed at this
# call site. Matrix rows from actions/ACTION_1.md S7/n6 (the doctor half).
class DoctorIndexDriftTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-index-drift")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def global_store = File.join(@home, "store")

  def doctor = Doctor.new(plastic_home: @home)

  def check(name) = doctor.check_done_signals.find { |c| c[:name] == name }

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

  def write_savepoint_done(id, disposition: "delivered")
    File.write(File.join(intent_dir(id), "savepoint.md"),
               "2026-07-03T00:00:00Z  Done  #{disposition}\n")
  end

  # --- 6.7: the finding excludes what savepoint_operational already reports --

  def test_drift_finding_excludes_what_savepoint_operational_reports
    write_index("101", section: "Active")
    write_intent_dir("101") # no savepoint.md at all - savepoint_operational's own concern
    result = check("index_ledger_drift")
    refute_nil result
    assert_equal "pass", result[:status]
    assert_empty result[:details] || []
  end

  # --- 6.8: emitted from check_done_signals, not doctor_core.rb --------------

  def test_finding_is_emitted_from_check_done_signals
    source = File.read(File.expand_path("../scripts/doctor.rb", __dir__))
    assert_match(/name: "index_ledger_drift"/, source)
    core_source = File.read(File.expand_path("../scripts/lib/doctor_core.rb", __dir__))
    refute_match(/index_ledger_drift/, core_source)
  end

  # --- 6.9: RuleCatalog::EXCLUDABLE_CHECKS is unchanged ------------------------

  def test_rule_catalog_excludable_checks_is_unchanged
    require_relative "../scripts/lib/rule_catalog"
    assert_equal %w[savepoint_operational backfilled_complete], RuleCatalog::EXCLUDABLE_CHECKS.keys
  end

  # --- 6.10: silent when INDEX and the ledgers agree ---------------------------

  def test_finding_is_silent_when_index_and_ledgers_agree
    write_index("101", section: "Completed")
    write_intent_dir("101")
    write_savepoint_done("101", disposition: "delivered")
    result = check("index_ledger_drift")
    assert_equal "pass", result[:status]
    assert_empty result[:details] || []
  end

  # --- 6.11: an empty store does not crash --------------------------------------

  def test_empty_store_does_not_crash
    write_index("999", section: "Active") # no matching directory anywhere
    result = nil
    begin
      result = check("index_ledger_drift")
    rescue StandardError => e
      flunk "expected no exception, got #{e.class}: #{e.message}"
    end
    refute_nil result
  end

  # --- 6.12: existing doctor findings are unchanged on a clean store -----------

  def test_existing_doctor_findings_are_unchanged_on_a_clean_store
    write_index("101", section: "Completed")
    write_intent_dir("101")
    write_savepoint_done("101", disposition: "delivered")
    names_without_drift = doctor.check_done_signals.map { |c| c[:name] } - ["index_ledger_drift"]
    assert_includes names_without_drift, "signals_agree"
    assert_includes names_without_drift, "savepoint_operational"
    assert_equal "pass", check("signals_agree")[:status]
  end

  # --- 6.7 (real conflict case, naming both sides) ------------------------------

  def test_a_real_terminal_conflict_is_reported
    write_index("101", section: "Active")
    write_intent_dir("101")
    write_savepoint_done("101", disposition: "delivered")
    result = check("index_ledger_drift")
    assert_equal "warn", result[:status]
    refute_empty result[:details]
  end
end
