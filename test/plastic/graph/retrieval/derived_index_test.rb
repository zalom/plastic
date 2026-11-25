# frozen_string_literal: true

require_relative "../../../test_helper"

# The passages and the search rows live in retrieval_graph.db, derived from the documents of knowledge.
class RetrievalDerivedIndexTest < Plastic::TestCase
  fixtures :empty

  def graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def passages = graphs.databases.fetch(:store).row("SELECT count(*) AS n FROM document_passages").fetch("n")

  def end_intent
    graphs.work.note_intent(graphs.retrieval.intent("1"), "Abandoned", "dropped because it ends")
    graphs.work.abandon_intent("1")
  end

  def hit_intents(terms) = graphs.retrieval.search_current(terms).map { |row| row.fetch("intent_id") }.uniq

  def stale_the_entries = graphs.databases.fetch(:store).transaction { |batch| batch.add("UPDATE document_fts SET sha256 = 'stale'") }

  def doctor = graphs.retrieval.repair

  def test_a_document_write_leaves_the_passage_count_unchanged
    graphs.work.write_intent(title: "Alpha needle")
    doctor
    before = passages
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK).write("1", "notes.md", "a second needle document")

    assert_equal before, passages
  end

  def test_a_new_intent_is_not_searchable_until_it_ends
    graphs.work.write_intent(title: "Alpha needle")

    assert_empty graphs.retrieval.search("needle")
    end_intent

    assert_equal ["1"], graphs.retrieval.search("needle").map { |row| row.fetch("intent_id") }.uniq
  end

  def test_a_deleted_retrieval_database_is_rebuilt_by_doctor_and_search_says_so_until_then
    graphs.work.write_intent(title: "Alpha needle")
    end_intent
    lose_retrieval_file

    error = assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { graphs.retrieval.search_current("needle") }
    assert_match(/plastic doctor/, error.message)
    doctor

    assert_equal ["1"], hit_intents("needle")
  end

  def test_a_hit_whose_hash_is_not_the_current_head_is_dropped
    graphs.work.write_intent(title: "Alpha needle")
    end_intent
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_database, origin, clock: FixedClock::CLOCK).write("1", "notes.md", "another body")

    stale_the_entries

    assert_empty graphs.retrieval.search("needle")
  end

  def test_contexts_and_discoveries_stay_in_knowledge
    names = graphs.databases.fetch(:store).rows("SELECT name FROM sqlite_master WHERE type = 'table'").map { |row| row["name"] }

    assert_equal %w[retrieval_contexts retrieval_discoveries], names & %w[retrieval_contexts retrieval_discoveries]
    assert_empty names & %w[document_passages document_fts retrieval_schema retrieval_backfills]
  end

  def test_a_sync_down_ends_with_the_rebuild_of_the_index
    graphs.work.write_intent(title: "Alpha needle")
    work = graphs.work
    work.sync_apply(work.sync_plan(:down, {}))

    assert_operator passages, :>, 0
  end
end
