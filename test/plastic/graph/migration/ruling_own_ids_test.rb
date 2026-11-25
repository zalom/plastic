# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"
require_relative "../../../../lib/plastic/graph/knowledge/ruling/writer"

# Migration 20261124233000 strips from each stored ruling the leading copy of its own id that an agent typed into the
# text, the way plastic intent rule does, and from the ruled line of the work log that carries it. The label was an
# agent's mistake, so it keeps no copy, and its down removes the version alone.
class GraphRulingOwnIdsTest < Plastic::TestCase
  include PreviousStore

  VERSION = "20261124233000"
  RULINGS = [["1", "D1", "D1 D1: One lock serializes the calls"], ["1", "D2", "D2: The lock file sits outside"],
    ["1", "D3", "D3. A call waits"], ["2", "D1", "D1 - Ship it"], ["2", "D2", "Jev chose the lock"],
    ["2", "D3", "D12 stays binding"], ["3", "D1", "D1 through D8 in the intent file are binding."], ["3", "D2", "D2 — Retire the store worktrees"],
    ["3", "D3", "D3..D6: ruled in the intent record"], ["3", "D4", "D4 / D4a: a new skill"]].freeze
  LINES = [[1, "ruled", "D1 D1 D1: One lock serializes the calls"], [2, "ruled", "D2 D2: The lock file sits outside"],
    [3, "ruled", "D3 Jev chose it"], [4, "noted", "D1 D1 a note"], [5, "ruled", "D2 D2 — Retire the store worktrees"],
    [6, "ruled", "D1 D1 through D8 in the intent file are binding."]].freeze

  def seeded(rulings: RULINGS, lines: LINES)
    previous_home.tap do |home|
      SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
        rulings.each { |row| database.execute("INSERT INTO rulings (intent_id, id, text, at, origin_id) VALUES (?, ?, ?, 'then', 'o')", row) }
      end
      SQLite3::Database.open(alpha_file(home, "work_graph.db")) do |database|
        lines.each { |row| database.execute("INSERT INTO work_log (intent_id, position, at, kind, text, origin_id) VALUES ('1', ?, 'then', ?, ?, 'o')", row) }
      end
    end
  end

  def rulings(home) = alpha_rows(home, "knowledge_graph.db", "SELECT intent_id, id, text FROM rulings ORDER BY intent_id, id")

  def lines(home) = alpha_rows(home, "work_graph.db", "SELECT text FROM work_log ORDER BY position").flatten

  def own_id_left(home) = rulings(home).count { |_intent, id, text| Plastic::Graph::Knowledge::Ruling::Writer.own_text(text, id) != text }

  def test_no_stored_ruling_begins_with_its_own_id_after_the_migration
    home = seeded
    before = own_id_left(home)
    migrate_store(home)

    assert_equal [5, 0, true], [before, own_id_left(home), recorded(home).include?(VERSION)]
  end

  def test_the_migration_strips_the_leading_id_and_leaves_every_other_text
    home = seeded
    migrate_store(home)

    assert_equal [["1", "D1", "One lock serializes the calls"], ["1", "D2", "The lock file sits outside"], ["1", "D3", "A call waits"],
      ["2", "D1", "Ship it"], ["2", "D2", "Jev chose the lock"], ["2", "D3", "D12 stays binding"],
      ["3", "D1", "D1 through D8 in the intent file are binding."], ["3", "D2", "Retire the store worktrees"], ["3", "D3", "D3..D6: ruled in the intent record"],
      ["3", "D4", "D4 / D4a: a new skill"]], rulings(home)
  end

  def test_the_migration_strips_the_copy_from_each_ruled_line_of_the_work_log
    home = seeded
    migrate_store(home)

    assert_equal ["D1 One lock serializes the calls", "D2 The lock file sits outside", "D3 Jev chose it", "D1 D1 a note", "D2 Retire the store worktrees",
      "D1 D1 through D8 in the intent file are binding."], lines(home)
  end

  def test_the_migration_names_what_it_stripped_and_the_sync_down_to_run
    report = migrate_store(seeded)

    assert_includes report.notes, "migrate: alpha stripped the leading own id from 5 rulings and 3 work log lines, an agent's mistake with no copy " \
                                  "and no undo; run plastic store sync down --project alpha so the printed work.log files carry them"
  end

  def test_the_note_counts_one_ruling_and_one_line_in_the_singular
    report = migrate_store(seeded(rulings: [["1", "D1", "D1: Go"]], lines: [[1, "ruled", "D1 D1: Go"]]))

    assert_includes report.notes, "migrate: alpha stripped the leading own id from 1 ruling and 1 work log line, an agent's mistake with no copy " \
                                  "and no undo; run plastic store sync down --project alpha so the printed work.log files carry them"
  end

  def test_a_store_with_no_ruling_to_strip_says_nothing
    report = migrate_store(previous_home)

    assert_empty report.notes.grep(/own id/)
  end

  def test_the_migration_keeps_no_copy_in_legacy_db
    home = seeded
    migrate_store(home)

    refute_path_exists alpha_file(home, "legacy.db")
  end

  def test_a_down_removes_the_version_alone_and_the_text_stays_stripped
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    # The placeholder and fold migrations are newer, so their downs come first.
    undone = 3.times.map { Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call }.last

    assert_equal [VERSION, {}, false, 0], [undone.version, undone.moved, recorded(home).include?(VERSION), own_id_left(home)]
  end
end
