# frozen_string_literal: true

require "digest"
require "sqlite3"
require_relative "../../../../test_helper"

# Store migration 2 is frozen: a digest pins its text, and it runs on a real work database.
class SchemaStore2Test < Plastic::TestCase
  Sequences = Plastic::Graph::SchemaSequences
  Store1 = Plastic::Graph::SchemaStore1

  PINNED = "bfef532e6ef8fd580fb9d0ff1cac97a6e05b3b49e3badcd13e6db9a1b2037b48"

  ROWS = [
    ["1", "n1", "done", "agent-7", 2, "2026-10-20T08:00:00Z"],
    ["1", "n2", "claimed", "s-4", 1, "2026-10-21T08:00:00Z"],
    ["1", "n3", "failed", "s-5", 3, "2026-10-22T08:00:00Z"],
    ["1", "n4", "open", nil, 0, "2026-10-23T08:00:00Z"],
    ["1", "n5", "open", "s-6", 1, "2026-10-24T08:00:00Z"]
  ].freeze

  def setup
    super
    @database = SQLite3::Database.new(":memory:")
    @database.execute_batch(Store1::Layout::TEXT.fetch(:work))
    @database.execute("PRAGMA user_version = 1")
    ROWS.each do |row|
      @database.execute('INSERT INTO nodes (intent_id, id, state, "by", retries, updated_at, origin_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [*row, "o"])
    end
  end

  def migrate = Sequences.migrate(@database, Sequences::SEQUENCES.fetch(:store), :work)

  def runs = @database.execute("SELECT node_id, number, agent, session_id, started_at, ended_at, result FROM runs ORDER BY node_id, number")

  def node_columns = @database.execute("PRAGMA table_info(nodes)").map { |column| column[1] }

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal PINNED, Digest::SHA256.hexdigest(Plastic::Graph::SchemaStore2.texts.join("\n--\n"))
  end

  def test_the_migration_never_reads_the_live_schema
    source = File.read(File.join(__dir__, "../../../../../lib/plastic/graph/schema/sequences/store_2.rb"))

    refute_match(/Schema\.(fetch|ddl|prepare)/, source)
  end

  def test_the_node_gains_its_claim_columns
    migrate

    assert_empty %w[claimed_by claimed_at seen_at answered_at] - node_columns
  end

  def test_the_node_loses_its_holder_and_its_count
    migrate

    assert_empty node_columns & %w[by retries]
  end

  def test_a_connection_that_returns_rows_by_name_runs_the_migration_too
    @database.results_as_hash = true
    migrate
    @database.results_as_hash = false

    assert_equal [2, [], 4], [@database.get_first_value("PRAGMA user_version"), node_columns & %w[by retries], runs.size]
  end

  def test_a_node_with_a_holder_gets_one_run_that_the_state_closes
    migrate

    assert_equal [["n1", 1, "", "agent-7", "2026-10-20T08:00:00Z", "2026-10-20T08:00:00Z", "done"],
      ["n2", 1, "", "s-4", "2026-10-21T08:00:00Z", nil, nil],
      ["n3", 1, "", "s-5", "2026-10-22T08:00:00Z", "2026-10-22T08:00:00Z", "failed"],
      ["n5", 1, "", "s-6", "2026-10-24T08:00:00Z", "2026-10-24T08:00:00Z", "released"]], runs
  end

  def test_a_claimed_node_keeps_its_claim_and_the_others_hold_none
    migrate

    assert_equal [["n2", "s-4", "2026-10-21T08:00:00Z"]],
      @database.execute("SELECT id, claimed_by, claimed_at FROM nodes WHERE claimed_by IS NOT NULL")
  end

  def test_the_runs_table_is_made_and_the_stamp_is_the_number
    migrate

    assert_equal 2, @database.get_first_value("PRAGMA user_version")
  end

  def test_a_second_run_changes_nothing
    migrate
    before = runs
    Plastic::Graph::SchemaStore2.apply(@database, :work)

    assert_equal before, runs
  end
end
