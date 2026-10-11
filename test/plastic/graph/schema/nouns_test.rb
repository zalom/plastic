# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/schema"

class SchemaNounsTest < Minitest::Test
  def test_every_declared_table_has_a_noun
    declared = Plastic::Graph::Schema.tables.keys + Plastic::Graph::SchemaCatalog::VIRTUAL.keys
    nouns = Plastic::Graph::Schema.nouns

    declared.each do |name|
      forms = nouns.fetch(name.to_s) { flunk "#{name} has no noun in schema/metadata.rb" }

      assert_equal 2, forms.size, name
      assert forms.none?(&:empty?), name
    end
  end

  def test_tally_names_a_document_head_in_plain_words
    assert_equal "1 document head", Plastic::Graph::Schema.tally(:document_heads, 1)
    assert_equal "2 document heads", Plastic::Graph::Schema.tally(:document_heads, 2)
  end
end
