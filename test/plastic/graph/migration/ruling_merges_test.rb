# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"

# Migration 20261125110000 merges each ruling that replaced another into the decision it replaced: the oldest ruling of
# each chain of supersedes links keeps its number and takes the text, the time and the session of the newest, the newer
# rulings and their supersedes links go, and the column supersedes is dropped. Its down adds the column back empty.
class GraphRulingMergesTest < Plastic::TestCase
  include BackupHomes
  include PreviousStore

  VERSION = "20261125110000"
  RULINGS = [["1", "D1", "Old", nil, "t1", "s1"], ["1", "D2", "New", "D1", "t2", "s2"], ["1", "D3", "Other", nil, "t3", "s3"],
    ["2", "D1", "First", nil, "t4", "s4"], ["2", "D2", "Second", "D1", "t5", "s5"], ["2", "D3", "Third", "D2", "t6", "s6"]].freeze
  LINKS = [["1/D2", "1/D1", "supersedes"], ["2/D2", "2/D1", "supersedes"], ["2/D3", "2/D2", "supersedes"],
    ["1/D3", "1", "cites"], ["5", "4", "supersedes"]].freeze

  def seeded(rulings: RULINGS, links: LINKS)
    previous_home.tap do |home|
      SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) do |database|
        rulings.each { |row| database.execute("INSERT INTO rulings (intent_id, id, text, supersedes, at, session_id, origin_id) VALUES (?, ?, ?, ?, ?, ?, 'o')", row) }
        links.each { |row| database.execute("INSERT INTO links (from_ref, to_ref, kind, at, origin_id) VALUES (?, ?, ?, 'then', 'o')", row) }
      end
    end
  end

  def rulings(home) = alpha_rows(home, "knowledge_graph.db", "SELECT intent_id, id, text, at, session_id FROM rulings ORDER BY intent_id, id")

  def links(home) = alpha_rows(home, "knowledge_graph.db", "SELECT from_ref, to_ref, kind FROM links ORDER BY from_ref")

  def columns(home) = alpha_rows(home, "knowledge_graph.db", "SELECT name FROM pragma_table_info('rulings')").flatten

  def fresh_columns
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    columns(home)
  end

  def down(home) = Plastic::Graph::MigrationDown.new(home, "alpha", MIGRATED_AT).call

  def test_a_new_store_has_no_supersedes_column_on_a_ruling
    refute_includes fresh_columns, "supersedes"
  end

  def test_the_oldest_ruling_of_each_chain_takes_the_text_time_and_session_of_the_newest
    home = seeded
    migrate_store(home)

    assert_equal [["1", "D1", "New", "t2", "s2"], ["1", "D3", "Other", "t3", "s3"], ["2", "D1", "Third", "t6", "s6"]], rulings(home)
  end

  def test_the_supersedes_links_of_rulings_go_and_every_other_link_stays
    home = seeded
    migrate_store(home)

    assert_equal [["1/D3", "1", "cites"], ["5", "4", "supersedes"]], links(home)
  end

  def test_the_migration_drops_the_column_and_leaves_the_layout_of_a_new_store
    home = seeded
    before = columns(home)
    migrate_store(home)

    assert_equal [true, fresh_columns, true], [before.include?("supersedes"), columns(home), recorded(home).include?(VERSION)]
  end

  def test_the_migration_names_what_it_merged_and_the_sync_down_to_run
    report = migrate_store(seeded)

    assert_includes report.notes, "migrate: alpha merged 3 rulings that replaced another into the 2 decisions they replaced; " \
                                  "run plastic store sync down --project alpha so the index of the store drops their links"
  end

  def test_the_note_counts_one_ruling_and_one_decision_in_the_singular
    report = migrate_store(seeded(rulings: RULINGS.first(2), links: LINKS.first(1)))

    assert_includes report.notes, "migrate: alpha merged 1 ruling that replaced another into the 1 decision it replaced; " \
                                  "run plastic store sync down --project alpha so the index of the store drops its link"
  end

  def test_a_link_from_a_ruling_that_no_row_holds_merges_nothing_and_goes
    home = seeded(rulings: RULINGS.first(1), links: LINKS.first(1))
    report = migrate_store(home)

    assert_equal [[["1", "D1", "Old", "t1", "s1"]], [], []], [rulings(home), links(home), report.notes.grep(/merged/)]
  end

  def test_a_store_with_no_ruling_that_replaced_another_says_nothing
    assert_empty migrate_store(previous_home).notes.grep(/merged/)
  end

  def test_the_migration_keeps_no_copy_in_legacy_db
    home = seeded
    migrate_store(home)

    refute_path_exists alpha_file(home, "legacy.db")
  end

  def test_a_down_adds_the_column_back_empty_and_removes_the_version
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    undone = down(home)

    assert_equal [VERSION, {}, false, true], [undone.version, undone.moved, recorded(home).include?(VERSION), columns(home).include?("supersedes")]
    assert_equal [nil], alpha_rows(home, "knowledge_graph.db", "SELECT DISTINCT supersedes FROM rulings").flatten
  end

  def test_a_down_and_an_update_give_back_the_migrated_store
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    before = rulings(home)
    down(home)
    migrate_store(home)

    assert_equal [fresh_columns, before], [columns(home), rulings(home)]
  end
end
