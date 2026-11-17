# frozen_string_literal: true

require "digest"
require_relative "../../../../test_helper"
require_relative "../../../../test_helpers/frozen_store"

# Store migration 4 is frozen: a digest pins its text, and it moves the intent rows from the work file to the knowledge file.
class SchemaStore4Test < Plastic::TestCase
  include FrozenStore

  Sequences = Plastic::Graph::SchemaSequences
  MOVED = %w[intents clusters completions approvals verdicts archives archive_entries work_log_pending].freeze

  def setup
    super
    build_pair
  end

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal "pinned-after-landing", Digest::SHA256.hexdigest(Plastic::Graph::SchemaStore4.texts.join("\n--\n"))
  end

  def test_the_migration_never_reads_the_live_schema
    source = File.read(File.join(__dir__, "../../../../../lib/plastic/graph/schema/sequences/store_4.rb"))

    refute_match(/Schema\.(fetch|ddl|prepare)|ATTACH|FOREIGN KEY/, source)
  end

  def test_the_knowledge_step_creates_the_moved_tables_empty
    Plastic::Graph::SchemaStore4.apply(@knowledge, :knowledge, {})

    assert_equal MOVED.to_h { |table| [table, 0] }, MOVED.to_h { |table| [table, count(@knowledge, table)] }
  end

  def test_every_moved_row_is_in_knowledge_with_equal_bytes_and_work_drops_the_tables
    Plastic::Graph::SchemaStore4.apply(@knowledge, :knowledge, {})
    before = @work.execute("SELECT * FROM archive_entries")
    migrate_work

    assert_equal before, @knowledge.execute("SELECT * FROM archive_entries")
    assert_equal [2, 1, 1, 1, 1, 1, 1, 1], MOVED.map { |table| count(@knowledge, table) }
    assert_empty tables(@work) & MOVED
    assert_equal 1, count(@work, "nodes")
  end

  def test_the_printed_and_changes_rows_of_the_moved_paths_move_and_the_others_stay
    Plastic::Graph::SchemaStore4.apply(@knowledge, :knowledge, {})
    migrate_work

    assert_equal %w[1--alpha/graph.json store/index.json], @knowledge.execute("SELECT path FROM printed ORDER BY path").map { |row| row["path"] }
    assert_equal %w[1--alpha/work.log roadmaps/r.md], @work.execute("SELECT path FROM printed ORDER BY path").map { |row| row["path"] }
    assert_equal ["intents"], @knowledge.execute("SELECT \"table\" FROM changes").map { |row| row["table"] }
    assert_equal ["nodes"], @work.execute("SELECT \"table\" FROM changes").map { |row| row["table"] }
  end

  def test_a_second_run_changes_nothing
    Plastic::Graph::SchemaStore4.apply(@knowledge, :knowledge, {})
    migrate_work
    before = @knowledge.execute("SELECT * FROM intents")
    migrate_work

    assert_equal before, @knowledge.execute("SELECT * FROM intents")
  end

  def test_a_stop_between_the_copy_and_the_drop_leaves_work_whole_and_the_rerun_copies_again_and_drops
    Plastic::Graph::SchemaStore4.apply(@knowledge, :knowledge, {})
    stop = -> { raise IOError, "killed" }
    assert_raises(IOError) { Plastic::Graph::SchemaStore4.apply(@work, :work, { knowledge: knowledge_path }, between: stop) }
    assert_equal [2, 2], [count(@work, "intents"), count(@knowledge, "intents")]
    migrate_work

    assert_equal [2, false], [count(@knowledge, "intents"), tables(@work).include?("intents")]
  end

  def test_a_digest_that_differs_raises_and_leaves_work_as_it_was
    Plastic::Graph::SchemaStore4.apply(@knowledge, :knowledge, {})
    @knowledge.execute("CREATE TRIGGER lose AFTER INSERT ON intents WHEN NEW.intent_id = '2' BEGIN DELETE FROM intents WHERE intent_id = '2'; END")

    error = assert_raises(Plastic::Graph::SchemaStore4::Mismatch) { migrate_work }

    assert_match(/intents/, error.message)
    assert_equal [2, 3], [count(@work, "intents"), @work.get_first_value("PRAGMA user_version")]
  end

  def test_a_connection_that_returns_rows_by_name_runs_the_migration_through_the_runner_sequence
    Plastic::Graph::SchemaSequences.migrate(@knowledge, Sequences::SEQUENCES.fetch(:store).first(4), :knowledge)
    Plastic::Graph::SchemaSequences.migrate(@work, Sequences::SEQUENCES.fetch(:store).first(4), :work, { knowledge: knowledge_path })

    assert_equal [4, 4], [@work, @knowledge].map { |database| database.get_first_value("PRAGMA user_version") }
    assert_equal 2, count(@knowledge, "intents")
  end
end
