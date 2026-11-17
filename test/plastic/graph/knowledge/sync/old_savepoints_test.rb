# frozen_string_literal: true

require "digest"
require_relative "../../../../test_helper"

# work.log is printed from the rows, read back by sync up, and replaces savepoint.md on a sync down.
class SyncOldSavepointsTest < Plastic::TestCase
  def sync_down = plastic("sync", "down", table: Plastic::CLI::TABLE)

  def log_path(intent) = "#{intent.dir}/work.log"

  def old_path(intent) = "#{intent.dir}/savepoint.md"

  def log_lines(id = "1") = retrieval.work_log(id)

  def old_print(intent, text)
    write(old_path(intent), text)
    store_graphs.databases.fetch(:store).transaction { |batch| batch.put(:printed, { path: old_path(intent), sha256: Digest::SHA256.hexdigest(text), at: Plastic.timestamp(FixedClock::AT) }) }
  end

  def test_an_intent_prints_work_log_and_no_savepoint_file
    intent = open_intent

    assert_equal [true, false], [folder.exist?(log_path(intent)), folder.exist?(old_path(intent))]
    assert_match(/\A- \S+ - - - opened - - Opened: Alpha\n\z/, folder.read(log_path(intent)))
  end

  def test_the_printed_file_reads_back_into_the_same_rows
    intent = open_intent
    before = log_lines.map(&:to_h)
    write(log_path(intent), folder.read(log_path(intent)).sub("Opened: Alpha", "Opened: Alpha, edited"))
    sync_up

    assert_equal [before.first.merge(text: "Opened: Alpha, edited")], log_lines.map(&:to_h)
  end

  def test_a_line_that_does_not_parse_becomes_a_noted_row_and_prints_as_one
    intent = open_intent
    write(log_path(intent), "#{folder.read(log_path(intent))}a loose line a person typed\n")
    sync_up

    assert_equal ["noted", "a loose line a person typed"], log_lines.last.values_at(:kind, :text)
    assert_match(/noted - - a loose line a person typed\n\z/, folder.read(log_path(intent)))
  end

  def test_an_old_savepoint_file_read_by_sync_up_adds_its_lines_as_noted_rows_once
    intent = open_intent
    write(old_path(intent), "2026-10-01T10:00:00+02:00  Spec written\nfree text\n")
    2.times { sync_up }

    assert_equal [%w[noted Spec\ written], %w[noted free\ text]], log_lines.drop(1).map { |line| line.values_at(:kind, :text) }
  end

  def test_sync_down_removes_the_savepoint_file_whose_hash_is_the_printed_one_and_prints_work_log
    intent = open_intent
    folder.delete(log_path(intent))
    old_print(intent, "2026-10-01T10:00:00+02:00  Opened: Alpha\n")

    assert_call sync_down, code: 0, out: ["removed #{old_path(intent)}"]
    assert_equal [false, true], [folder.exist?(old_path(intent)), folder.exist?(log_path(intent))]
  end

  def test_sync_down_keeps_a_savepoint_file_changed_by_hand_and_names_it
    intent = open_intent
    old_print(intent, "2026-10-01T10:00:00+02:00  Opened: Alpha\n")
    write(old_path(intent), "a line a person added\n")
    result = sync_down

    assert_call result, code: 0, out: [old_path(intent)]
    assert_equal "a line a person added\n", folder.read(old_path(intent))
  end

  def test_no_other_command_removes_a_savepoint_file
    intent = open_intent
    old_print(intent, "2026-10-01T10:00:00+02:00  Opened: Alpha\n")
    plastic("intent", "rule", intent.intent_id, "A ruling", table: Plastic::CLI::TABLE)

    assert folder.exist?(old_path(intent))
  end

  def test_a_file_this_home_never_printed_is_named_as_never_printed
    intent = open_intent
    write(old_path(intent), "2026-10-01T10:00:00+02:00  Opened: Alpha\n")

    assert_call sync_down, code: 0, out: ["kept #{old_path(intent)}: never printed by this home"]
  end

  def test_a_file_changed_by_hand_is_named_as_changed_by_hand
    intent = open_intent
    old_print(intent, "2026-10-01T10:00:00+02:00  Opened: Alpha\n")
    write(old_path(intent), "a line a person added\n")

    assert_call sync_down, code: 0, out: ["kept #{old_path(intent)}: changed by hand"]
  end

  def test_removing_the_file_removes_its_printed_row_too
    intent = open_intent
    old_print(intent, "2026-10-01T10:00:00+02:00  Opened: Alpha\n")

    assert retrieval.printed.key?(old_path(intent))
    sync_down

    refute retrieval.printed.key?(old_path(intent))
  end
end
