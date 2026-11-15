# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderIntentFileContextTest < Plastic::TestCase
  fixtures :alpha

  DIR = "store/1--alpha"

  def read_in(rel, bytes)
    write("#{DIR}/#{rel}", bytes)
    read = Plastic::Graph::Knowledge::Reader.new(folder, { "1" => retrieval.intent("1") }, origin, retrieval:).read("#{DIR}/#{rel}")
    apply_read(read)
    read.database
  end

  def test_context_json_cannot_become_a_document
    assert_equal :knowledge, read_in("context.json", JSON.generate("intent" => "1", "context" => {}))
    assert_empty retrieval.documents("1").select { |document| document.path == "context.json" }
  end

  def test_context_json_with_no_row_reads_the_context_and_the_discovery_rows
    read_in("context.json", JSON.generate("intent" => "1", "discovery" => { "a" => 1 }, "context" => { "b" => 2 }))

    assert_equal [{ "a" => 1 }, { "b" => 2 }], [JSON.parse(retrieval.discoveries("1").first.data), JSON.parse(retrieval.contexts("1").first.data)]
  end

  def test_context_json_with_a_row_replaces_the_row_and_the_rows_of_the_part_it_lacks
    read_in("context.json", JSON.generate("intent" => "1", "discovery" => { "a" => 1 }, "context" => { "b" => 2 }))
    read_in("context.json", JSON.generate("intent" => "1", "context" => { "b" => 3 }))

    assert_equal [{ "b" => 3 }, []], [JSON.parse(retrieval.contexts("1").first.data), retrieval.discoveries("1")]
  end

  def test_context_json_that_names_another_intent_is_refused
    assert_raises(Plastic::Invalid) { read_in("context.json", JSON.generate("intent" => "2", "context" => {})) }
    assert_empty retrieval.contexts("1")
  end

  def test_context_json_that_is_not_json_is_refused
    assert_raises(Plastic::Invalid) { read_in("context.json", "{nope") }
  end
end
