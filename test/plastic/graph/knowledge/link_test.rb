# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeLinkTest < Plastic::TestCase
  Knowledge = Plastic::Graph::Knowledge

  def test_the_intent_of_a_link_is_the_first_segment_of_its_from_ref
    links = ["1/D2", "4"].map { |from_ref| Knowledge::Link.from_h({ from_ref: }) }

    assert_equal %w[1 4], links.map(&:from_intent_id)
  end

  def test_a_link_joins_the_ends_and_the_kind_it_was_written_with
    link = Knowledge::Link.from_h({ from_ref: "1", to_ref: "2", kind: "chain" })

    assert_equal [true, false], [link.joins?(%w[1 2 chain]), link.joins?(%w[1 2 cites])]
  end

  def test_a_link_read_from_the_index_stores_its_time_in_utc
    link = Knowledge::Link.from_entry({ "from_ref" => "1", "to_ref" => "2", "kind" => "chain", "at" => "2026-10-05T10:00:00+02:00" }, "now")

    assert_equal "2026-10-05T08:00:00Z", link[:at]
  end

  def test_a_link_read_from_the_index_with_an_impossible_time_is_refused
    error = assert_raises(Plastic::Invalid) { Knowledge::Link.from_entry({ "from_ref" => "1", "to_ref" => "2", "kind" => "chain", "at" => "2026-10-05T25:00:00+02:00" }, "now") }

    assert_equal "2026-10-05T25:00:00+02:00 is not a time", error.message
  end

  def test_an_edge_is_complete_with_two_refs_and_a_known_kind
    assert_equal [{ from_ref: "1", to_ref: "2", kind: "chain", at: "now" }, nil, nil], [Knowledge::Link.from_entry({ "from_ref" => "1", "to_ref" => "2", "kind" => "chain" }, "now"), Knowledge::Link.from_entry({ "from_ref" => "1", "to_ref" => "", "kind" => "chain" }, "now"), Knowledge::Link.from_entry({ "from_ref" => "1", "to_ref" => "2", "kind" => "other" }, "now")]
  end
end
