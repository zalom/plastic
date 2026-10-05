# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/discovery_candidates"

class DiscoveryCandidatesTest < Plastic::TestCase
  def rows(terms) = Plastic::Workflows::DiscoveryCandidates.new("global", retrieval).rows(terms)

  def test_each_match_carries_its_store_rank_score_and_reference
    intent = open_intent

    row = sole(rows("alpha"))

    assert_equal ["global", 1, 1.0 / 61, false], row.values_at("store", "local_rank", "rrf_score", "archived")
    assert_equal retrieval.reference("1", intent.file).fetch(:uri), row.fetch("uri")
  end

  def test_an_archived_intent_is_marked
    open_intent
    store_graphs.databases[:work].transaction { |batch| batch.put(:archives, { intent_id: "1", at: STAMP }) }

    assert sole(rows("alpha")).fetch("archived")
  end

  def test_no_match_gives_no_rows
    open_intent

    assert_empty rows("absent")
  end
end
