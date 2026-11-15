# frozen_string_literal: true

require_relative "../../../command_reference_helper"

class CommandReferenceTouchesModeTest < Minitest::Test
  include CommandReferenceHelper

  def schema = CommandReference::Schema.new(CommandReferenceHelper::ROOT)

  def test_the_schema_names_the_table_a_trigger_writes
    assert_equal %w[document_fts], schema.triggered("document_heads")
  end

  def test_a_table_with_no_trigger_writes_no_other_table
    assert_empty schema.triggered("nodes")
  end

  def test_a_command_that_writes_a_document_head_lists_the_search_table_its_trigger_writes
    touches = page("intent new").touches

    assert touches.writes?("knowledge_graph.db", "document_heads")
    assert touches.writes?("knowledge_graph.db", "document_fts")
  end
end
