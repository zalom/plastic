# frozen_string_literal: true

require_relative "../../../test_helper"

class RetrievalExactLookupPlansTest < Plastic::TestCase
  def plans = Plastic::Graph::Retrieval::ExactLookupPlans.new(store_graphs.databases, origin).rows("1", "plan.md")

  def test_the_intent_lookup_searches_by_index
    assert_match(/\ASEARCH intents USING/, plans.first.map { |row| row.fetch("detail") }.join)
  end

  def test_the_document_lookup_searches_by_index
    assert_match(/\ASEARCH documents USING/, plans.last.map { |row| row.fetch("detail") }.join)
  end
end
