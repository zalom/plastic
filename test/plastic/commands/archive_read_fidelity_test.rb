# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_archive"

class ArchiveReadFidelityTest < Plastic::TestCase
  def test_archive_reads_return_snapshot_bytes_without_mutating_archive_state
    intent = archived_intent_with_unsynced_text
    before = archive_read_state(intent)

    assert_equal expected_bodies, read_bytes(intent)
    assert_equal before, archive_read_state(intent)
  end

  private

  def archived_intent_with_unsynced_text
    open_intent("Snapshot", status: "future").tap do |intent|
      write("#{intent.dir}/#{intent.file}", "Hand-edited archive evidence\n")
      write("#{intent.dir}/research.txt", "New archive evidence\n")
      result = plastic("intent", "archive", intent.intent_id, table: Plastic::CLI::TABLE)

      assert_equal 0, result.code, result.err
    end
  end

  def expected_rows(intent)
    [[intent.file, "Hand-edited archive evidence\n"], ["research.txt", "New archive evidence\n"]]
  end

  def expected_bodies = ["Hand-edited archive evidence\n", "New archive evidence\n"]

  def read_bytes(intent)
    assert_equal expected_rows(intent), retrieval.search("archive evidence").map { |row| row.values_at("path", "body") }.sort
    [retrieval.fetch(intent.intent_id, intent.file), retrieval.fetch(intent.intent_id, "research.txt")].map(&:body)
  end

  def archive_read_state(intent)
    work = store_graphs.databases.fetch(:work)
    archive_rows = work.rows("SELECT * FROM archives WHERE intent_id = :id ORDER BY intent_id", id: intent.intent_id)
    entry_rows = work.rows("SELECT * FROM archive_entries WHERE intent_id = :id ORDER BY path", id: intent.intent_id)
    changes = { work: work.rows("SELECT * FROM changes ORDER BY seq"),
                knowledge: store_graphs.databases.fetch(:knowledge).rows("SELECT * FROM changes ORDER BY seq") }
    { archive_rows:, entry_rows:, changes:, filesystem: filesystem_state(intent) }
  end

  def filesystem_state(intent)
    { exists: folder.exist?(intent.dir), files: snapshot(folder.path("store")) }
  end
end
