# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/context_persistence"

class KnowledgeReaderContextFileTest < Plastic::TestCase
  ContextFile = Plastic::Graph::Knowledge::Reader::ContextFile
  PATH = "store/1--alpha/context.json"

  def file(text, intent_id = "1") = ContextFile.new(text, intent_id, PATH)

  def test_a_json_list_is_not_a_context_file
    assert_equal "#{PATH} is not a JSON object", file("[1]").problem
  end

  def test_an_object_that_holds_neither_part_has_no_problem_and_no_rows
    found = file('{"note": 1}')

    assert_equal [nil, {}], [found.problem, found.rows]
  end

  def test_an_object_that_names_another_intent_is_refused
    assert_equal "#{PATH} names intent 2, not intent 1", file('{"intent": "2", "context": {"a": 1}}').problem
  end

  def test_an_object_for_this_intent_gives_one_row_for_each_part
    assert_equal %i[retrieval_contexts retrieval_discoveries], file('{"intent": "1", "context": {"a": 1}, "discovery": {"b": 2}}').rows.keys.sort
  end

  def test_text_that_is_not_json_is_named
    assert_equal "#{PATH} is not JSON", file("{nope").problem
  end

  def written_context_text
    open_intent
    Plastic::Workflows::ContextPersistence.new(call_context(intent_id: "1")).persist({ "evidence" => [], "facts" => ["a fact"] })
    store_graphs.databases.fetch(:store).row("SELECT data FROM retrieval_contexts WHERE intent_id = '1'").fetch("data")
  end

  def test_the_context_row_read_from_the_printed_file_holds_the_text_the_writer_stores
    written = written_context_text
    printed = Plastic::Graph::Prints::ContextPrint.call(retrieval.intent("1"), Plastic::Graph::Prints::Contents.read(retrieval, "1"))

    assert_equal written, file(sole(printed).text).rows.fetch(:retrieval_contexts).fetch(:data)
  end
end
