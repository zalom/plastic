# frozen_string_literal: true

require_relative "../../test_helper"

class PrintsLegacyTest < Plastic::TestCase
  PATH = "store/1--one/plan.md"

  def legacy_row(path, body) = { intent_id: "1", path:, body:, updated_at: STAMP }

  def put(table, row) = store_graphs.databases[:knowledge].transaction { |batch| batch.put(table, row) }

  def plan_prints = Plastic::Graph::Prints.of_intent(retrieval, retrieval.intent("1")).select { |print| print.path == PATH }

  def test_an_intent_prints_its_legacy_files_byte_for_byte
    open_intent("One")
    body = "# Plan\r\n\n  trailing  \n"
    put(:legacy_intents_data, legacy_row("plan.md", body))
    print = plan_prints.first

    assert_equal [:knowledge, body, Digest::SHA256.hexdigest(body)], [print.database, print.text, print.sha256]
  end

  def test_a_path_with_a_document_and_a_legacy_row_prints_from_the_legacy_row
    open_intent("One")
    put(:documents, { intent_id: "1", path: "plan.md", body: "from documents\n", updated_at: STAMP })
    put(:legacy_intents_data, legacy_row("plan.md", "from legacy\n"))

    assert_equal ["from legacy\n"], plan_prints.map(&:text)
  end

  def test_the_store_prints_a_path_with_both_rows_once
    open_intent("One")
    put(:documents, { intent_id: "1", path: "plan.md", body: "from documents\n", updated_at: STAMP })
    put(:legacy_intents_data, legacy_row("plan.md", "from legacy\n"))

    assert_equal 1, Plastic::Graph::Prints.of_store(retrieval).count { |print| print.path == PATH }
  end
end
