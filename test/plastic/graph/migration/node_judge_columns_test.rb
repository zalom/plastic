# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/previous_store"

# Migration 20261123100000 drops the columns judge and verdict of the nodes table. No code reads them and no real store fills them.
class GraphNodeJudgeColumnsTest < Plastic::TestCase
  include BackupHomes
  include PreviousStore

  NOW = Time.utc(2026, 11, 23, 12, 0, 0)
  GONE = %w[judge verdict].freeze
  ROW = "INSERT INTO nodes (intent_id, id, kind, title, state, findings, origin_id, judge, verdict) VALUES ('1', 'n1', 'work', 'Build', 'done', 'green', 'o', NULL, NULL)"

  def columns(home) = alpha_rows(home, "work_graph.db", "SELECT name FROM pragma_table_info('nodes')").flatten

  def seeded
    previous_home.tap { |home| SQLite3::Database.open(alpha_file(home, "work_graph.db")) { |database| database.execute(ROW) } }
  end

  def down(home) = Plastic::Graph::MigrationDown.new(home, "alpha", NOW).call

  # The empty roadmap tables, node inputs, deadline and driver migrations are the newest, so four more downs come first.
  def drivers_down(home) = 8.times { down(home) }

  def test_a_new_store_has_no_judge_or_verdict_column_on_a_node
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)

    assert_empty GONE & columns(home)
  end

  def test_a_node_row_has_no_judge_or_verdict_member
    assert_empty GONE.map(&:to_sym) & Plastic::Graph::Work::Node.members
  end

  def test_the_migration_has_no_switch
    refute_includes Plastic::Graph::MigrationList::HELD.keys, NODES
  end

  def test_the_migration_drops_the_two_columns_and_leaves_the_layout_of_a_new_store
    home = previous_home
    before = columns(home)
    migrate_store(home)

    assert_equal [GONE, GONE.size], [GONE & before, ((before - columns(home)) - ["input"]).size]
    assert_equal fresh_columns, columns(home)
  end

  def test_the_migration_keeps_each_node_row_and_records_its_version
    home = seeded
    migrate_store(home)

    assert_equal [[["1", "n1", "Build", "green"]], true], [alpha_rows(home, "work_graph.db", "SELECT intent_id, id, title, findings FROM nodes"), recorded(home).include?(NODES)]
  end

  def test_the_migration_is_backed_up_first_with_the_columns_in_the_backup
    home = seeded
    migrate_store(home)

    refute_empty backup_folders(home)
  end

  def test_a_down_puts_the_empty_columns_back_and_removes_the_version
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    drivers_down(home)
    down(home)
    undone = down(home)

    assert_equal [NODES, {}, true, false], [undone.version, undone.moved, GONE.all? { |name| columns(home).include?(name) }, recorded(home).include?(NODES)]
  end

  def test_a_down_keeps_each_node_row
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    drivers_down(home)
    down(home)
    down(home)

    assert_equal [["1", "n1", "Build", nil, nil]], alpha_rows(home, "work_graph.db", "SELECT intent_id, id, title, judge, verdict FROM nodes")
  end

  def test_a_down_and_an_update_give_back_the_migrated_store
    home = seeded.tap { |seeded_home| migrate_store(seeded_home) }
    before = alpha_rows(home, "work_graph.db", "SELECT * FROM nodes")
    drivers_down(home)
    down(home)
    migrate_store(home)

    assert_equal [fresh_columns, before], [columns(home), alpha_rows(home, "work_graph.db", "SELECT * FROM nodes")]
  end

  def fresh_columns
    home = fresh_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    columns(home)
  end
end

# A graph file an earlier release printed holds judge and verdict on each node; it still reads, and the rows have neither.
class GraphNodeJudgeColumnsPrintTest < Plastic::TestCase
  GraphFile = Plastic::Graph::Knowledge::Reader::GraphFile
  PATH = "store/1--alpha/graph.json"

  def node_hash(**fields)
    { "intent_id" => "1", "id" => "n1", "kind" => "work", "title" => "Build", "criterion" => nil, "state" => "done", "input" => nil, "output" => nil,
      "question" => nil, "answer" => nil, "reason" => nil, "findings" => "ok", "updated_at" => "2026-10-20T08:00:00Z" }.merge(fields)
  end

  def text(node) = "#{JSON.pretty_generate({ "intent" => "1", "nodes" => [node], "edges" => [] })}\n"

  def test_a_node_printed_with_judge_and_verdict_has_no_unknown_field
    assert_empty GraphFile.new(text(node_hash("judge" => nil, "verdict" => nil)), "1", nil, PATH).problems
  end

  def test_a_node_printed_without_them_reads_the_same
    assert_empty GraphFile.new(text(node_hash), "1", nil, PATH).problems
  end
end
