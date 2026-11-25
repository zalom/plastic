# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"

# Migration 20261125100000 deletes each ruling whose whole text is three dots, a placeholder an agent wrote by mistake,
# with every link that names it. It keeps no copy, and its down removes the version alone.
class GraphPlaceholderRulingsTest < Plastic::TestCase
  include PreviousStore

  VERSION = "20261125100000"
  RULINGS = [["1", "D1", "..."], ["1", "D2", "Ship it..."], ["1", "D3", "... and the rest waits"], ["2", "D1", "..."], ["2", "D2", "Wait"]].freeze
  LINKS = [["1/D1", "1", "cites"], ["2", "1/D1", "answers"], ["1/D2", "1", "cites"]].freeze

  def seeded(rulings: RULINGS)
    previous_home.tap do |home|
      SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
        rulings.each { |row| database.execute("INSERT INTO rulings (intent_id, id, text, at, origin_id) VALUES (?, ?, ?, 'then', 'o')", row) }
        LINKS.each { |row| database.execute("INSERT INTO links (from_ref, to_ref, kind, at, origin_id) VALUES (?, ?, ?, 'then', 'o')", row) }
      end
    end
  end

  def rulings(home) = alpha_rows(home, "knowledge_graph.db", "SELECT intent_id, id, text FROM rulings ORDER BY intent_id, id")

  def links(home) = alpha_rows(home, "knowledge_graph.db", "SELECT from_ref, to_ref, kind FROM links ORDER BY from_ref")

  def test_the_migration_deletes_each_placeholder_and_keeps_every_other_ruling
    home = seeded
    migrate_store(home)

    assert_equal [[["1", "D2", "Ship it..."], ["1", "D3", "... and the rest waits"], ["2", "D2", "Wait"]], true],
      [rulings(home), recorded(home).include?(VERSION)]
  end

  def test_the_migration_deletes_each_link_that_names_a_placeholder
    home = seeded
    migrate_store(home)

    assert_equal [["1/D2", "1", "cites"]], links(home)
  end

  def test_the_migration_says_how_many_it_deleted
    report = migrate_store(seeded)

    assert_includes report.notes, "migrate: alpha deleted 2 rulings whose whole text is ..., placeholders an agent wrote by mistake, " \
                                  "with no copy and no undo"
  end

  def test_the_note_counts_one_placeholder_in_the_singular
    report = migrate_store(seeded(rulings: [["1", "D1", "..."]]))

    assert_includes report.notes, "migrate: alpha deleted 1 ruling whose whole text is ..., a placeholder an agent wrote by mistake, " \
                                  "with no copy and no undo"
  end

  def test_a_store_with_no_placeholder_says_nothing
    assert_empty migrate_store(previous_home).notes.grep(/placeholder/)
  end

  def test_the_migration_keeps_no_copy_in_legacy_db
    home = seeded
    migrate_store(home)

    refute_path_exists alpha_file(home, "legacy.db")
  end

  def test_a_down_removes_the_version_alone_and_the_placeholders_stay_deleted
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    # The merge migration is newer, so its down comes first.
    undone = 2.times.map { Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call }.last

    assert_equal [VERSION, {}, false, 3], [undone.version, undone.moved, recorded(home).include?(VERSION), rulings(home).size]
  end
end
