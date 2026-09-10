# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/index_projection"

# IndexProjection (intent 337, n5): computes every intent's status from its
# own savepoint.md ledger, reads the status INDEX.md currently claims, and
# returns both plus the drift between them. The ledger wins WHERE THE LEDGER
# SPEAKS - an intent whose ledger is absent or silent keeps the status INDEX
# already carries (row 5.13, folded at the 2026-09-10 plan review). Matrix
# rows from actions/ACTION_1.md S3/n5. Hermetic: every fixture lives in a
# Dir.mktmpdir; this module never reads the real ~/.plastic.
class IndexProjectionTest < Minitest::Test
  def setup
    @store = Dir.mktmpdir("index-projection")
  end

  def teardown
    FileUtils.remove_entry(@store) if @store && Dir.exist?(@store)
  end

  def write_index(active: [], future: [], completed: [], abandoned: [])
    line = ->(id) { "- [#{id} - Title](store/#{id}--slug/#{id}--slug.md) - 2026-09-09 note." }
    lines = ["# Index", "", "## Active", ""]
    active.each { |id| lines << line.call(id) }
    lines += ["", "## Future", ""]
    future.each { |id| lines << line.call(id) }
    lines += ["", "## Clusters", "", "## Abandoned", ""]
    abandoned.each { |id| lines << line.call(id) }
    lines += ["", "## Completed", ""]
    completed.each { |id| lines << line.call(id) }
    File.write(File.join(@store, "INDEX.md"), lines.join("\n") + "\n")
  end

  def write_intent(id, savepoint_lines: nil)
    dir = File.join(@store, "#{id}--slug")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--slug.md"), "# #{id}\n") unless savepoint_lines == :no_dir
    return if savepoint_lines.nil?

    File.write(File.join(dir, "savepoint.md"), savepoint_lines.join("\n") + "\n")
  end

  def write_exclusions(*lines)
    File.write(File.join(@store, "doctor-exclusions"), lines.join("\n") + "\n")
  end

  # --- 5.1: status from the LAST terminal ledger line -------------------------

  def test_status_comes_from_the_last_terminal_ledger_line
    write_index(active: ["101"])
    write_intent("101", savepoint_lines: [
                   "2026-01-01T00:00:00Z  Done  delivered",
                   "2026-02-01T00:00:00Z  Exec  reopened",
                   "2026-03-01T00:00:00Z  Done  abandoned",
                 ])
    result = IndexProjection.analyze(@store)
    row = result[:drift].find { |r| r[:id] == "101" }
    assert_equal "Abandoned", row[:ledger_status]
  end

  # --- 5.2: Done delivered -> Completed, Done abandoned -> Abandoned ----------

  def test_delivered_and_abandoned_map_to_their_own_sections
    write_index(active: %w[101 102])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    write_intent("102", savepoint_lines: ["2026-01-01T00:00:00Z  Done  abandoned"])
    result = IndexProjection.analyze(@store)
    ids_status = result[:drift].each_with_object({}) { |r, h| h[r[:id]] = r[:ledger_status] }
    assert_equal "Completed", ids_status["101"]
    assert_equal "Abandoned", ids_status["102"]
  end

  # --- 5.3: no terminal line projects Active, never a false drift -------------

  def test_intent_without_a_terminal_line_projects_active
    write_index(completed: ["101"])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Exec  started"])
    result = IndexProjection.analyze(@store)
    refute(result[:drift].any? { |r| r[:id] == "101" })
  end

  # --- 5.4: no savepoint.md is reported unknown, never raised -----------------

  def test_intent_without_a_savepoint_is_reported_unknown_not_raised
    write_index(active: ["101"])
    write_intent("101", savepoint_lines: nil)
    result = nil
    begin
      result = IndexProjection.analyze(@store)
    rescue StandardError => e
      flunk "expected no exception, got #{e.class}: #{e.message}"
    end
    refute(result[:drift].any? { |r| r[:id] == "101" })
  end

  # --- 5.5: Future intents are not reported as drift ---------------------------

  def test_future_intents_are_not_reported_as_drift
    write_index(future: ["101"])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    result = IndexProjection.analyze(@store)
    refute(result[:drift].any? { |r| r[:id] == "101" })
  end

  # --- 5.6: a torn ledger line is excluded from the status ---------------------

  def test_torn_ledger_line_is_excluded_from_the_projection
    write_index(active: ["101"])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    # A torn write: the process died mid-append, leaving a partial line with
    # no trailing newline. It must never be read as a real "abandoned" line.
    File.open(File.join(@store, "101--slug", "savepoint.md"), "a") { |f| f.write("2026-02-01T00:00:00Z  Done  aban") }
    result = IndexProjection.analyze(@store)
    row = result[:drift].find { |r| r[:id] == "101" }
    assert_equal "Completed", row[:ledger_status]
  end

  # --- 5.7: an invalid UTF-8 byte does not raise -------------------------------

  def test_invalid_utf8_byte_does_not_raise
    write_index(active: ["101"])
    write_intent("101", savepoint_lines: nil)
    dir = File.join(@store, "101--slug")
    File.open(File.join(dir, "savepoint.md"), "wb") do |f|
      f.write("2026-01-01T00:00:00Z  Done  delivered\n\xFF\xFEbad\n")
    end
    result = nil
    assert_silent_of_raise { result = IndexProjection.analyze(@store) }
    refute_nil result
  end

  def assert_silent_of_raise
    yield
  rescue StandardError => e
    flunk "expected no exception, got #{e.class}: #{e.message}"
  end

  # --- 5.8: an INDEX entry with no store directory is reported -----------------

  def test_index_entry_without_a_directory_is_reported
    write_index(active: ["999"])
    result = IndexProjection.analyze(@store)
    assert_includes result[:index_only].map { |r| r[:id] }, "999"
  end

  # --- 5.9: a store directory INDEX does not list is reported ------------------

  def test_directory_missing_from_index_is_reported
    write_index
    write_intent("777", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    result = IndexProjection.analyze(@store)
    assert_includes result[:directory_only].map { |r| r[:id] }, "777"
  end

  # --- 5.10: a drift row names both sides ---------------------------------------

  def test_drift_row_names_the_index_status_and_the_ledger_status
    write_index(active: ["101"])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    result = IndexProjection.analyze(@store)
    row = result[:drift].find { |r| r[:id] == "101" }
    assert_equal "Active", row[:index_status]
    assert_equal "Completed", row[:ledger_status]
  end

  # --- 5.11: analyze writes nothing ---------------------------------------------

  def test_analyze_writes_no_file
    write_index(active: ["101"])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    before = Dir.glob(File.join(@store, "**", "*")).map { |p| [p, File.exist?(p) ? File.mtime(p) : nil] }
    IndexProjection.analyze(@store)
    after = Dir.glob(File.join(@store, "**", "*")).map { |p| [p, File.exist?(p) ? File.mtime(p) : nil] }
    assert_equal before, after
  end

  # --- 5.12: doctor exclusions (savepoint_operational, backfilled_complete) ----

  def test_excluded_directories_are_skipped
    write_index # 101 unlisted, so without the exclusion it would be directory_only
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    write_exclusions("savepoint_operational 101")
    result = IndexProjection.analyze(@store)
    refute_includes result[:directory_only].map { |r| r[:id] }, "101"
  end

  # --- 5.13: a silent or absent ledger keeps the INDEX status ------------------

  def test_silent_or_absent_ledger_keeps_the_index_status
    write_index(completed: %w[101 102])
    write_intent("101", savepoint_lines: nil) # no savepoint.md at all
    write_intent("102", savepoint_lines: ["2026-01-01T00:00:00Z  Exec  started"]) # no terminal line
    result = IndexProjection.analyze(@store)
    refute(result[:drift].any? { |r| r[:id] == "101" })
    refute(result[:drift].any? { |r| r[:id] == "102" })
  end

  # --- 5.14: a Done detail that is not exactly a disposition is classified -----

  def test_done_detail_is_classified_by_prefix_or_reported_indeterminate
    write_index(active: %w[101 102 103])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered (merge 6e2b2ca to main)"])
    write_intent("102", savepoint_lines: ["2026-01-01T00:00:00Z  Done  merged to main at 690c696; suite green"])
    write_intent("103", savepoint_lines: ["2026-01-01T00:00:00Z  Done  outcome.md written"])
    result = IndexProjection.analyze(@store)
    ids_status = result[:drift].each_with_object({}) { |r, h| h[r[:id]] = r[:ledger_status] }
    assert_equal "Completed", ids_status["101"]
    assert_equal "Completed", ids_status["102"]
    refute ids_status.key?("103") # indeterminate: never reported as drift
  end

  # --- 5.15: drift totals exclude what savepoint_operational already reports ---

  def test_drift_rows_exclude_what_savepoint_operational_already_reports
    write_index(active: %w[101 102])
    write_intent("101", savepoint_lines: nil) # missing savepoint - savepoint_operational's own concern
    write_intent("102", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"]) # real drift
    result = IndexProjection.analyze(@store)
    ids = result[:drift].map { |r| r[:id] }
    refute_includes ids, "101"
    assert_includes ids, "102"
  end
end
