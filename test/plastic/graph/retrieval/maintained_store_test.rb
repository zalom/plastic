# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/retrieval/maintained_store"

class RetrievalMaintainedStoreTest < Plastic::TestCase
  def refusal(slug) = assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { Plastic::Graph::Retrieval::MaintainedStore.new(@plastic_home, slug).verify }

  def test_a_store_whose_retrieval_file_is_gone_is_refused_with_its_slug
    lose_retrieval_file
    error = refusal("global")

    assert_equal ["global", "retrieval maintenance is required before source global can be read"], [error.slug, error.message]
  end

  def test_a_store_missing_a_database_is_refused_with_its_slug
    assert_equal "missing", refusal("missing").slug
  end

  def test_a_backfilled_store_is_maintained
    Plastic::Graph.create(home: @plastic_home, store: "ready")

    assert_nil Plastic::Graph::Retrieval::MaintainedStore.new(@plastic_home, "ready").verify
  end
end
