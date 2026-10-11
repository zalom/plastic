# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/retrieval/maintained_store"

class RetrievalMaintainedStoreTest < Plastic::TestCase
  def opened(slug)
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", slug))
    Plastic::Graph.open(home: @plastic_home, store: slug)
  end

  def refusal(slug) = assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { Plastic::Graph::Retrieval::MaintainedStore.new(@plastic_home, slug).verify }

  def test_a_store_with_no_backfill_marker_is_refused_with_its_slug
    opened("old").databases.each_value { |database| database.rows("SELECT 1") }
    error = refusal("old")

    assert_equal ["old", "retrieval maintenance is required before source old can be read"], [error.slug, error.message]
  end

  def test_a_store_missing_a_database_is_refused_with_its_slug
    assert_equal "missing", refusal("missing").slug
  end

  def test_a_backfilled_store_is_maintained
    opened("ready").retrieval.backfill

    assert_nil Plastic::Graph::Retrieval::MaintainedStore.new(@plastic_home, "ready").verify
  end
end
