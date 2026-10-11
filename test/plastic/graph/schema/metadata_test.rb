# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/schema"

class SchemaMetadataTest < Minitest::Test
  def test_every_declared_table_has_a_singular_and_a_plural_noun
    declared = (Plastic::Graph::Schema.tables.keys + Plastic::Graph::SchemaCatalog::VIRTUAL.keys).map(&:to_s)
    nouns = Plastic::Graph::Schema.nouns

    refute_empty declared
    assert_empty declared.reject { |name| nouns.fetch(name, []).count { |form| !form.empty? } == 2 }
  end

  def test_tally_names_a_document_head_in_plain_words
    assert_equal "1 document head", Plastic::Graph::Schema.tally(:document_heads, 1)
    assert_equal "2 document heads", Plastic::Graph::Schema.tally(:document_heads, 2)
  end
end
