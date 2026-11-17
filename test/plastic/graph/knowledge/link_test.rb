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

  def test_a_link_joins_the_ends_and_the_kind_it_was_written_with
    link = Knowledge::Link.from_h({ from_ref: "1", to_ref: "2", kind: "chain" })

    assert_equal [true, false], [link.joins?(%w[1 2 chain]), link.joins?(%w[1 2 cites])]
  end

  def test_an_edge_is_complete_with_two_refs_and_a_known_kind
    assert_equal [true, false, false], [Knowledge::Link.complete?("1", "2", "chain"), Knowledge::Link.complete?("1", "", "chain"), Knowledge::Link.complete?("1", "2", "other")]
  end
end
