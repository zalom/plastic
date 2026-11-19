# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/migration_ledger"

class MigrationLedgerTest < Plastic::TestCase
  Ledger = Plastic::Graph::MigrationLedger
  NOW = Time.utc(2026, 11, 19, 12, 0, 0)

  def setup
    super
    @local = Plastic::Graph::Database.open_local(@plastic_home).fetch(:local)
  end

  def ledger = Ledger.new(@local, NOW)

  def trigger(sql) = @local.transaction { |batch| batch.add(sql) }

  def test_a_recorded_event_is_one_row_with_the_store_the_version_the_time_the_kept_rows_and_whether_it_can_be_undone
    ledger.record("alpha", "up", "20261119000000", moved: { "sqlar" => 2 }, undoable: true)

    assert_equal [["alpha", "20261119000000", "up", "2026-11-19T12:00:00Z", '{"sqlar":2}', 1]],
      @local.rows("SELECT store, version, event, at, moved, undoable FROM store_migrations").map(&:values)
  end

  def test_the_events_of_a_store_come_in_the_order_they_were_recorded_and_leave_out_other_stores
    ledger.record("alpha", "up", "20261119000000", moved: {}, undoable: true)
    ledger.record("beta", "up", "20261119000000", moved: {}, undoable: true)
    ledger.record("alpha", "down", "20261119000000", moved: { "sqlar" => 1 }, undoable: false)

    assert_equal [%w[up 20261119000000], %w[down 20261119000000]], ledger.of("alpha").map { |row| row.values_at("event", "version") }
  end

  def test_an_event_that_is_not_up_down_or_purge_is_refused
    assert_raises(Plastic::Graph::Database::Error) { ledger.record("alpha", "sideways", "20261119000000", moved: {}, undoable: false) }
  end

  def test_the_up_rows_of_one_store_are_written_together_or_not_at_all
    trigger("CREATE TRIGGER refuse BEFORE INSERT ON store_migrations WHEN NEW.version = '20261119000000' BEGIN SELECT RAISE(ABORT, 'refused'); END")
    entries = %w[20261117000000 20261119000000].map { |version| Plastic::Graph::LegacyKeep::Entry.new(version:, kept: {}, undoable: false) }

    assert_raises(Plastic::Graph::Database::Error, SQLite3::Exception) { ledger.ups("alpha", entries) }
    assert_empty ledger.of("alpha")
  end

  def test_a_write_that_fails_answers_its_reason_and_raises_nothing
    trigger("CREATE TRIGGER refuse BEFORE INSERT ON store_migrations BEGIN SELECT RAISE(ABORT, 'refused'); END")

    assert_equal "plastic.db: refused", Ledger.write(@plastic_home, NOW) { |ledger| ledger.record("alpha", "down", "20261119000000", moved: {}, undoable: false) }
  end

  def test_a_write_that_succeeds_answers_nil
    assert_nil Ledger.write(@plastic_home, NOW) { |ledger| ledger.record("alpha", "down", "20261119000000", moved: {}, undoable: false) }
  end
end
