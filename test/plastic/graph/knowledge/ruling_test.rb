# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeRulingTest < Plastic::TestCase
  def test_the_ref_of_a_ruling_names_its_intent_and_its_id
    assert_equal "4.1/D3", Plastic::Graph::Knowledge::Ruling.from_h({ intent_id: "4.1", id: "D3" }).ref
  end
end
