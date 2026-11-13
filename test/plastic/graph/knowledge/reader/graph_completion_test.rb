# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderGraphCompletionTest < Plastic::TestCase
  GRAPH = "store/1--alpha/graph.json"
  GraphFile = Plastic::Graph::Knowledge::Reader::GraphFile

  fixtures :alpha_synced

  def completion_hash(**fields)
    { "intent_id" => "1", "at" => "2026-10-20T09:00:00Z", "session_id" => "s1", "judge" => "verdict",
      "criteria" => "{}", "evidence" => "{}", "outcome_sha256" => "abc" }.merge(fields.transform_keys(&:to_s))
  end

  def graph_text(**parts) = "#{JSON.pretty_generate({ "intent" => "1" }.merge(parts.transform_keys(&:to_s)))}\n"

  def sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases)

  def read_up = sync.apply(sync.plan(:up))

  def put_completion
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.put(:completions, { intent_id: "1", origin_id: retrieval.origin_id, at: "2026-10-19T09:00:00Z", session_id: "s0", judge: "verdict",
                                criteria: "{}", evidence: "{}", outcome_sha256: "kept" })
    end
  end

  def test_a_completion_in_the_file_is_read_into_a_row_with_the_local_origin
    write(GRAPH, graph_text(completion: completion_hash))
    read_up

    assert_equal [["1", "s1", retrieval.origin_id]], store_graphs.databases.fetch(:work).rows("SELECT intent_id, session_id, origin_id FROM completions").map(&:values)
  end

  def test_a_file_without_the_completion_key_leaves_the_row_the_intent_held
    put_completion
    write(GRAPH, graph_text)
    read_up

    assert_equal ["kept"], store_graphs.databases.fetch(:work).rows("SELECT outcome_sha256 FROM completions").map { |row| row["outcome_sha256"] }
  end

  def test_a_null_completion_leaves_the_row_the_intent_held
    put_completion
    write(GRAPH, graph_text(completion: nil))
    read_up

    assert_equal 1, store_graphs.databases.fetch(:work).rows("SELECT * FROM completions").size
  end

  def test_a_completion_that_names_another_intent_is_refused
    text = graph_text(completion: completion_hash(intent_id: "2"))

    assert_equal ["#{GRAPH} holds a completion of intent \"2\", not 1"], GraphFile.new(text, "1", nil, GRAPH).problems
  end

  def test_a_completion_with_an_unknown_field_is_refused
    text = graph_text(completion: completion_hash(colour: "red"))

    assert_equal ["#{GRAPH} holds the unknown field colour in completions"], GraphFile.new(text, "1", nil, GRAPH).problems
  end
end
