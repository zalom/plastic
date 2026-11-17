# frozen_string_literal: true

require "digest"
require_relative "../../../../test_helper"

# Store migration 5 is frozen: a digest pins its text. It builds retrieval_graph.db from the documents and drops the derived tables from knowledge.
class SchemaStore5Test < Plastic::TestCase
  Layout = Plastic::Graph::SchemaStore1::Layout::TEXT
  Sequences = Plastic::Graph::SchemaSequences
  DERIVED = %w[document_passages document_fts retrieval_schema retrieval_backfills].freeze

  def setup
    super
    @folder = Dir.mktmpdir
    @knowledge = SQLite3::Database.new(File.join(@folder, "knowledge_graph.db"), results_as_hash: true)
    @knowledge.execute_batch(Layout.fetch(:knowledge) + Plastic::Graph::SchemaStore4::TEXT.fetch(:knowledge))
    seed
    @knowledge.execute("PRAGMA user_version = 4")
  end

  def seed
    %w[first second].each do |word|
      body = "# #{word} needle"
      sha = Digest::SHA256.hexdigest(body)
      @knowledge.execute("INSERT INTO documents (intent_id, path, body, origin_id) VALUES ('1', '#{word}.md', '#{body}', 'o')")
      @knowledge.execute("INSERT INTO document_revisions (sha256, intent_id, path, body, created_at, origin_id) VALUES ('#{sha}', '1', '#{word}.md', '#{body}', 't', 'o')")
      @knowledge.execute("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES ('1', '#{word}.md', '#{sha}', 't', 'o')")
      @knowledge.execute("INSERT INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id) VALUES ('#{sha}', '1', '#{word}.md', 0, '#{body}', 1, 1, 'o')")
      @knowledge.execute("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES ('#{body}', '1', '#{word}.md', '#{sha}', 0, 'o')")
    end
    @knowledge.execute("INSERT INTO retrieval_contexts (intent_id, origin_id, data, updated_at) VALUES ('1', 'o', '{}', 't')")
  end

  def retrieval_path = File.join(@folder, "retrieval_graph.db")

  def apply(**) = Plastic::Graph::SchemaStore5.apply(@knowledge, :knowledge, { knowledge: File.join(@folder, "knowledge_graph.db") }, **)

  def retrieval = SQLite3::Database.new(retrieval_path, results_as_hash: true)

  def tables(database) = database.execute("SELECT name FROM sqlite_master WHERE type IN ('table', 'trigger')").map { |row| row["name"] }

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal "d8bdfa692120d7dd7437a049a1648456417caffaaccb6f635bdff7ff4da4ef63", Digest::SHA256.hexdigest(Plastic::Graph::SchemaStore5.texts.join("\n--\n"))
  end

  def test_the_migration_never_reads_the_live_schema
    source = File.read(File.join(__dir__, "../../../../../lib/plastic/graph/schema/sequences/store_5.rb"))

    refute_match(/Schema\.(fetch|ddl|prepare)/, source)
  end

  def test_the_retrieval_file_holds_the_passages_and_the_search_rows_of_the_documents
    apply
    database = retrieval

    assert_equal [2, 2, 5], [database.get_first_value("SELECT count(*) FROM document_passages"), database.get_first_value("SELECT count(*) FROM document_fts"), database.get_first_value("PRAGMA user_version")]
  ensure
    database&.close
  end

  def test_knowledge_loses_the_derived_tables_and_triggers_and_keeps_contexts_and_documents
    apply
    names = tables(@knowledge)

    assert_empty names & [*DERIVED, "document_heads_search_insert", "document_heads_search_update", "document_heads_search_delete"]
    assert_equal %w[retrieval_contexts retrieval_discoveries documents document_revisions document_heads].sort, (names & %w[retrieval_contexts retrieval_discoveries documents document_revisions document_heads]).sort
  end

  def test_a_stop_after_the_build_leaves_knowledge_whole_and_the_rerun_builds_again
    assert_raises(IOError) { apply(between: -> { raise IOError, "killed" }) }
    @knowledge.execute("ROLLBACK") if @knowledge.transaction_active?

    assert_includes tables(@knowledge), "document_passages"
    apply
    database = retrieval

    assert_equal 2, database.get_first_value("SELECT count(*) FROM document_passages")
  ensure
    database&.close
  end

  def test_a_copy_that_differs_from_knowledge_raises_and_leaves_the_passages_in_knowledge
    database = retrieval
    database.execute_batch(Plastic::Graph::SchemaStore5::TEXT.fetch(:document_passages))
    database.execute("CREATE TRIGGER alter_copy AFTER INSERT ON document_passages BEGIN UPDATE document_passages SET body = 'altered' WHERE rowid = new.rowid; END")
    database.close

    assert_raises(Plastic::Graph::SchemaStore5::Mismatch) { apply }
    assert_includes tables(@knowledge), "document_passages"
  end

  def test_a_connection_that_returns_rows_as_lists_builds_the_same_file
    @knowledge.results_as_hash = false
    apply
    database = retrieval

    assert_equal [2, 2], [database.get_first_value("SELECT count(*) FROM document_passages"), database.get_first_value("SELECT count(*) FROM document_fts")]
  ensure
    database&.close
  end

  def test_the_other_files_take_no_part
    work = SQLite3::Database.new(":memory:", results_as_hash: true)

    assert_nil Plastic::Graph::SchemaStore5.apply(work, :work, {})
  end

  def test_a_connection_that_returns_rows_by_name_runs_the_migration_through_the_runner_sequence
    Sequences.migrate(@knowledge, Sequences::SEQUENCES.fetch(:store).first(5), :knowledge, { knowledge: File.join(@folder, "knowledge_graph.db") })

    assert_equal [5, true], [@knowledge.get_first_value("PRAGMA user_version"), File.file?(retrieval_path)]
  end
end
