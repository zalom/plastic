# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/resources/row_moves"

class KnowledgeResourcesRowMovesTest < Plastic::TestCase
  RowMoves = Plastic::Graph::Knowledge::Resources::RowMoves

  def tables(statements) = statements.map { |sql| sql[/\A(?:UPDATE|DELETE FROM) (\w+)/, 1] }

  def test_a_move_updates_the_documents_their_heads_the_kept_files_and_the_printed_files
    assert_equal %w[documents document_heads sqlar printed], tables(RowMoves.moving)
  end

  def test_a_drop_deletes_from_the_documents_their_heads_the_kept_files_and_the_printed_files
    assert_equal %w[documents document_heads sqlar printed], tables(RowMoves.dropping)
  end
end
