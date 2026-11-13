# frozen_string_literal: true

require_relative "../../test_helper"

class PrintsArchiveTest < Plastic::TestCase
  def index = JSON.parse(Plastic::Graph::Prints.index(store_graphs.retrieval).text)

  def completion_row(intent_id)
    { intent_id:, origin_id: retrieval.origin_id, at: "2026-10-20T09:00:00Z", session_id: "s1", judge: "verdict",
      criteria: "{}", evidence: "{}", outcome_sha256: "abc" }
  end

  def archive(intent_id, restored_at: nil)
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.put(:completions, completion_row(intent_id))
      batch.put(:archives, { intent_id:, at: "2026-10-21T09:00:00Z", origin_id: retrieval.origin_id, restored_at:, session_id: "s2" })
    end
  end

  def graph_text(intent) = Plastic::Graph::Prints.of_intent(retrieval, intent).find { |print| print.path.end_with?("graph.json") }.text

  def test_the_graph_file_prints_the_completion_of_a_done_intent
    intent = open_intent("Alpha", status: "done")
    store_graphs.databases.fetch(:work).transaction { |batch| batch.put(:completions, completion_row("1")) }

    printed = JSON.parse(graph_text(retrieval.intent(intent.intent_id))).fetch("completion")

    assert_equal ["1", "verdict", false], [*printed.values_at("intent_id", "judge"), printed.key?("origin_id")]
  end

  def test_the_graph_file_prints_a_null_completion_when_the_intent_has_none
    intent = open_intent

    assert_nil JSON.parse(graph_text(intent)).fetch("completion")
  end

  def test_the_index_lists_an_archived_intent_among_the_intents
    open_intent("Alpha", status: "done")
    archive("1")

    assert_equal ["1"], index.fetch("intents").map { |intent| intent.fetch("intent_id") }
  end

  def test_the_index_lists_the_intents_archived_now_with_their_completion
    open_intent("Alpha", status: "done")
    archive("1")
    entry = index.fetch("archives").first

    assert_equal ["1", "2026-10-21T09:00:00Z", "s2", "verdict"], entry.values_at("intent_id", "at", "session_id").push(entry.fetch("completion").fetch("judge"))
    refute entry.fetch("completion").key?("origin_id")
  end

  def test_the_index_leaves_out_an_archive_that_was_restored
    open_intent("Alpha", status: "done")
    archive("1", restored_at: "2026-10-22T09:00:00Z")

    assert_empty index.fetch("archives")
  end

  def test_the_index_lists_no_archives_when_none_exist
    open_intent

    assert_empty index.fetch("archives")
  end

  def test_the_store_prints_no_folder_files_for_an_archived_intent
    open_intent("Alpha", status: "done")
    archive("1")
    paths = Plastic::Graph::Prints.of_store(retrieval).map(&:path)

    assert_equal ["store/index.json"], paths
  end
end
