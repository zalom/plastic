# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/run"
require_relative "../../../../test_helpers/resources_homes"
require "delegate"

# A repair that rewrites a link in a core file of a closed intent says so on that intent's work log, in its output and in its preview.
class RepairRunAmendmentTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  Resources = Plastic::Graph::Knowledge::Resources
  REASON = Plastic::Layout.amendment_reason(:link)
  AMENDED = [
    ["spec.md", "spec.md: link reviews/r1.md -> resources/tmp/reviews/r1.md; #{REASON}"],
    ["spec.md", "spec.md: link resources/notes.md -> resources/tmp/notes.md; #{REASON}"]
  ].freeze

  def folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

  def repair = Plastic::Graph::Knowledge::Repair::Run.new(folder, store_graphs).call

  def close(status) = store_database.transaction { |batch| batch.write(:intents, "UPDATE intents SET status = :status WHERE intent_id = '1'", status:) }

  def amended = store_database.rows("SELECT path, text FROM work_log WHERE kind = 'amended' AND text LIKE '%: link %' ORDER BY position").map(&:values)

  def work_log = File.join(store_root, INTENT, "work.log")

  def preview_lines = Plastic::Graph::Knowledge::Sync::Preview.new(@plastic_home, "global", {}).call

  # A work graph whose amended lines cannot be written, as a locked database fails.
  class FailingWork < SimpleDelegator
    def amend_intents(_amendments) = raise(IOError, "the database is locked")
  end

  def setup
    super
    write_old_layout
  end

  def test_a_rewrite_in_a_core_file_of_a_done_intent_writes_one_amended_line_for_each_link
    close("done")
    repair

    assert_equal AMENDED, amended
  end

  def test_an_abandoned_intent_is_amended_too
    close("abandoned")
    repair

    assert_equal AMENDED, amended
  end

  def test_the_amended_line_holds_the_sha_of_the_new_text
    close("done")
    repair
    sha = store_database.rows("SELECT sha256 FROM work_log WHERE kind = 'amended' AND text LIKE '%: link %'").map { |row| row.fetch("sha256") }.uniq

    assert_equal [Digest::SHA256.hexdigest(File.read(File.join(store_root, INTENT, "spec.md")))], sha
  end

  def test_the_output_of_the_repair_lists_each_amendment
    close("done")

    assert_includes repair, "amended #{INTENT}/spec.md: link reviews/r1.md -> resources/tmp/reviews/r1.md; #{REASON}"
  end

  def test_an_open_intent_gets_no_amended_line
    repair

    assert_equal [], amended
  end

  def test_the_repair_prints_the_amended_lines_into_the_work_log_of_the_intent
    close("done")
    repair

    assert_equal 2, File.read(work_log).lines.grep(/ amended spec\.md sha256:\h+ spec\.md: link /).size
  end

  def test_after_the_repair_a_sync_up_has_nothing_pending_and_reads_a_hand_line
    close("done")
    repair
    pending = preview_lines.last
    File.write(work_log, "#{File.read(work_log)}- 2026-11-20T09:00:00+01:00 - - - noted - - a hand line\n")
    up = plastic("store", "sync", "up", table: Plastic::CLI::TABLE)

    assert_equal ["preview: paths that would change: 0", 0], [pending, up.code]
  end

  def test_the_same_link_twice_in_one_note_gives_one_amended_line
    write("#{INTENT}/spec.md", "# Spec\n\nSee [review](reviews/r1.md) and again [review](reviews/r1.md).\n")
    close("done")
    repair

    assert_equal [AMENDED.first], amended
  end

  def test_a_failed_amendment_puts_the_files_and_the_rows_back
    close("done")
    before = [files_without_databases, row_digest]
    graphs = store_graphs
    failing = graphs.with(work: FailingWork.new(graphs.work))

    assert_raises(IOError) { Plastic::Graph::Knowledge::Repair::Run.new(folder, failing).call }
    assert_equal before, [files_without_databases, row_digest]
  end

  def test_the_plan_names_each_amendment_before_anything_is_written
    close("done")
    before = files_without_databases
    plan = Resources::SortPlan.new(folder, closed: Set["1"])

    assert_equal ["preview: would amend #{INTENT}/spec.md: link reviews/r1.md -> resources/tmp/reviews/r1.md; #{REASON}",
      "preview: would amend #{INTENT}/spec.md: link resources/notes.md -> resources/tmp/notes.md; #{REASON}"], plan.amendments.map(&:preview)
    assert_equal [before, []], [files_without_databases, amended]
  end

  def fields = store_database.rows("SELECT old_text, new_text FROM work_log WHERE kind = 'amended' AND text LIKE '%: link %' ORDER BY position").map(&:values)

  FIELDS = [%w[reviews/r1.md resources/tmp/reviews/r1.md], %w[resources/notes.md resources/tmp/notes.md]].freeze

  def test_the_row_of_a_link_change_holds_the_old_and_the_new_link_as_fields
    close("done")
    repair

    assert_equal FIELDS, fields
  end

  def test_the_old_and_the_new_link_stay_when_a_sync_up_reads_the_work_log_back
    close("done")
    repair
    File.write(work_log, "#{File.read(work_log)}- 2026-11-20T09:00:00+01:00 - - - noted - - a hand line\n")
    plastic("store", "sync", "up", table: Plastic::CLI::TABLE)

    assert_equal FIELDS, fields
  end

  def test_the_structural_changes_of_a_done_intent_are_one_amended_line
    close("done")
    repair
    lines = store_database.rows("SELECT path, text FROM work_log WHERE kind = 'amended' AND text NOT LIKE '%: link %'").map(&:values)

    assert_equal [1, ""], [lines.size, lines.first.first]
  end

  def test_an_empty_gitkeep_in_an_old_actions_folder_is_removed
    write("#{INTENT}/actions/.gitkeep", "")
    repair

    assert_equal [false, false], [File.exist?(File.join(store_root, INTENT, "actions/.gitkeep")),
      File.exist?(File.join(store_root, INTENT, "resources/references/actions/.gitkeep"))]
  end
end
