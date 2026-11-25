# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/migration_down"

class GraphUtcTimesTest < Plastic::TestCase
  include PreviousStore

  NOW = Time.utc(2026, 11, 21, 12, 0, 0)
  KNOWLEDGE = <<~SQL
    INSERT INTO intents (intent_id, origin_id, slug, title, status, opened_at, closed_at, updated_at) VALUES
      ('91', 'o', '91--a', 'A', 'open', '2026-10-05', '2026-10-05T03:00:00-05:00', '2026-10-05T10:00:00+02:00'),
      ('92', 'o', '92--b', 'B', 'open', '2026-10-06', NULL, '2026-10-06T08:00:00Z');
  SQL
  WORK = "INSERT INTO work_log (intent_id, position, at, kind, origin_id) VALUES ('91', 1, '2026-10-05T10:00:00+02:00', 'noted', 'o')"
  BEFORE = [[["2026-10-05", "2026-10-05T03:00:00-05:00", "2026-10-05T10:00:00+02:00"], ["2026-10-06", nil, "2026-10-06T08:00:00Z"]],
    ["2026-10-05T10:00:00+02:00"]].freeze
  AFTER = [[["2026-10-05", "2026-10-05T08:00:00Z", "2026-10-05T08:00:00Z"], ["2026-10-06", nil, "2026-10-06T08:00:00Z"]],
    ["2026-10-05T08:00:00Z"]].freeze

  SHARED = <<~SQL
    INSERT INTO intents (intent_id, origin_id, slug, title, status, opened_at, updated_at) VALUES
      ('93', 'o', '93--c', 'C', 'open', '2026-10-07', '2026-10-07T09:00:00+01:00'),
      ('94', 'o', '94--d', 'D', 'open', '2026-10-07', '2026-10-07T08:00:00Z');
  SQL
  UNREADABLE = "INSERT INTO intents (intent_id, origin_id, slug, title, status, opened_at, updated_at) VALUES ('95', 'o', '95--e', 'E', 'open', '2026-10-08', '2026-10-08T25:00:00+02:00')"

  # A store of the previous release whose rows hold times with an offset, a date, a time in UTC and no time.
  def seeded_home
    previous_home.tap do |home|
      SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute_batch(KNOWLEDGE) }
      SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute(WORK) }
    end
  end

  def migrated = seeded_home.tap { |home| migrate_store(home) }

  def with_rows(home, sql) = home.tap { SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute_batch(sql) } }

  ROADMAP_TABLES = %w[roadmaps batches roadmap_items roadmap_edges roadmap_log written_needs_links].freeze

  def times(home)
    [alpha_rows(home, "knowledge_graph.db", "SELECT opened_at, closed_at, updated_at FROM intents WHERE intent_id IN ('91', '92') ORDER BY intent_id"),
      alpha_rows(home, "work_graph.db", "SELECT at FROM work_log WHERE intent_id = '91'").flatten]
  end

  def down(home) = Plastic::Graph::MigrationDown.new(without_usage(home), "alpha", NOW).call

  # Every table, but the five roadmap tables and the table the roadmap migration makes from them: the down of the empty roadmap tables migration builds them empty, and the next run keeps them as empty copies in legacy.db. The down of the leftover work tables migration leaves an empty sqlite_sequence in work_graph.db.
  def contents(home, name) = alpha_rows(home, name, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").flatten.to_h { |table| [table, alpha_rows(home, name, "SELECT * FROM \"#{table}\"").sort_by(&:inspect)] }.reject { |table, rows| ROADMAP_TABLES.any? { |name| table.start_with?(name) } || (table == "sqlite_sequence" && rows.empty?) }

  def test_the_migration_writes_every_time_with_an_offset_in_utc_and_leaves_dates_utc_times_and_blanks
    assert_equal AFTER, times(migrated)
  end

  def test_the_migration_says_how_many_times_it_wrote_in_utc
    assert_includes migrate_store(seeded_home).notes, "migrate: alpha wrote 3 times in UTC"
  end

  def test_the_migration_keeps_each_old_text_in_legacy_db
    kept = alpha_rows(migrated, "legacy.db", "SELECT schema_name, table_name, column_name, row_key, old, new FROM changed_values_#{UTC} ORDER BY 1, 2, 3")

    assert_equal [["main", "intents", "closed_at", '["91","o"]', "2026-10-05T03:00:00-05:00", "2026-10-05T08:00:00Z"],
      ["main", "intents", "updated_at", '["91","o"]', "2026-10-05T10:00:00+02:00", "2026-10-05T08:00:00Z"],
      ["work", "work_log", "at", '["91",1,"o"]', "2026-10-05T10:00:00+02:00", "2026-10-05T08:00:00Z"]], kept
  end

  def test_the_ledger_records_the_migration_as_one_a_down_can_undo
    row = ledger_rows(migrated).find { |_store, version| version == UTC }

    assert_equal ["up", 1], row.values_at(2, 4)
  end

  def test_a_down_puts_each_old_text_back_and_drops_what_legacy_db_kept
    home = migrated
    undone = down(home)

    assert_equal [UTC, { "changed_values" => 3 }, BEFORE, false, false],
      [undone.version, undone.moved, times(home), recorded(home).include?(UTC), legacy_tables(home).include?("changed_values_#{UTC}")]
  end

  def test_a_down_puts_an_old_text_back_only_on_the_row_it_came_from
    home = with_rows(seeded_home, SHARED)
    migrate_store(home)
    down(home)

    assert_equal [["93", "2026-10-07T09:00:00+01:00"], ["94", "2026-10-07T08:00:00Z"]],
      alpha_rows(home, "knowledge_graph.db", "SELECT intent_id, updated_at FROM intents WHERE intent_id IN ('93', '94') ORDER BY intent_id")
  end

  def test_the_migration_leaves_a_time_it_cannot_read_as_it_was
    home = with_rows(seeded_home, UNREADABLE)
    migrate_store(home)

    assert_equal [["2026-10-08T25:00:00+02:00"]], alpha_rows(home, "knowledge_graph.db", "SELECT updated_at FROM intents WHERE intent_id = '95'")
  end

  def test_the_migration_names_each_time_it_cannot_read
    notes = migrate_store(with_rows(seeded_home, UNREADABLE)).notes

    assert_includes notes, "migrate: alpha wrote 3 times in UTC and left 1 unreadable time unchanged: main.intents.updated_at 2026-10-08T25:00:00+02:00"
  end

  def test_a_down_keeps_a_time_written_after_the_migration
    home = migrated
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("UPDATE intents SET updated_at = '2026-11-21T10:00:00Z' WHERE intent_id = '91'") }
    down(home)

    assert_equal ["2026-10-05T03:00:00-05:00", "2026-11-21T10:00:00Z"], times(home).first.first.drop(1)
  end

  def test_a_down_and_then_an_update_give_back_the_migrated_store
    home = migrated
    before = %w[knowledge_graph.db work_graph.db legacy.db].map { |name| contents(home, name) }
    down(home)
    migrate_store(home)

    assert_equal before, %w[knowledge_graph.db work_graph.db legacy.db].map { |name| contents(home, name) }
  end

  def test_a_store_with_no_time_to_change_can_still_go_down
    home = previous_home.tap { |previous| migrate_store(previous) }

    assert_equal [UTC, {}], down(home).then { |undone| [undone.version, undone.moved] }
  end
end

class GraphUtcTimesNothingToChangeTest < Plastic::TestCase
  include PreviousStore

  NOW = Time.utc(2026, 11, 21, 12, 0, 0)

  # A store this release made, with the time migration taken off its records, so the migration runs on rows that hold no time with an offset.
  def store_before_utc_alone
    home = File.join(Dir.mktmpdir, ".plastic")
    FileUtils.mkdir_p(File.join(home, "stores", "alpha"))
    File.write(File.join(home, "projects.yml"), "projects:\n  alpha:\n    path: #{Dir.mktmpdir}\n")
    Plastic::Graph.create(home:, store: "alpha")
    forget(home)
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute("DELETE FROM schema_migrations WHERE version = ?", [UTC]) }
    home
  end

  def down(home) = Plastic::Graph::MigrationDown.new(without_usage(home), "alpha", NOW).call

  def test_a_migration_with_no_time_to_change_makes_no_legacy_db
    home = store_before_utc_alone
    migrate_store(home)

    refute_path_exists alpha_file(home, "legacy.db")
  end

  def test_a_migration_with_no_time_to_change_goes_down_by_removing_its_version_alone
    home = store_before_utc_alone.tap { |fresh| migrate_store(fresh) }
    undone = down(home)

    assert_equal [UTC, {}, false, false], [undone.version, undone.moved, recorded(home).include?(UTC), File.exist?(alpha_file(home, "legacy.db"))]
  end
end

class GraphUtcTimesResultTest < Plastic::TestCase
  def test_the_line_names_one_time_in_the_singular_and_no_time_not_at_all
    lines = [1, 0].map { |changed| Plastic::Graph::UtcTimes::Result.new(changed:).line("alpha") }

    assert_equal ["migrate: alpha wrote 1 time in UTC", nil], lines
  end

  def test_the_line_names_the_unreadable_times_with_or_without_a_time_written
    lines = [3, 0].map { |changed| Plastic::Graph::UtcTimes::Result.new(changed:, unreadable: ["main.a.at x", "main.b.at y"]).line("alpha") }

    assert_equal ["migrate: alpha wrote 3 times in UTC and left 2 unreadable times unchanged: main.a.at x, main.b.at y",
      "migrate: alpha left 2 unreadable times unchanged: main.a.at x, main.b.at y"], lines
  end
end
