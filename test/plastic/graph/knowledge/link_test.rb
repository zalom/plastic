# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeLinkTest < Plastic::TestCase
  Knowledge = Plastic::Graph::Knowledge

  def test_the_intent_of_a_link_is_the_first_segment_of_its_from_ref
    links = ["1/D2", "4"].map { |from_ref| Knowledge::Link.from_h({ from_ref: }) }

    assert_equal %w[1 4], links.map(&:from_intent_id)
  end

  def test_a_supersedes_row_points_from_the_newer_ruling_to_the_older
    newer, older = %w[D2 D1].map { |id| Knowledge::Ruling.from_h({ intent_id: "1", id:, at: STAMP }) }

    assert_equal({ from_ref: "1/D2", to_ref: "1/D1", kind: "supersedes", at: STAMP }, Knowledge::Link.supersedes(newer, older))
  end
end
