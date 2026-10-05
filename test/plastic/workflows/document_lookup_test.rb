# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/document_lookup"

class DocumentLookupTest < Plastic::TestCase
  def setup
    super
    @reference = retrieval.reference("1", open_intent.file).fetch(:uri)
  end

  def lookup = Plastic::Workflows::DocumentLookup.new(call_context(harness: scoped_harness(slug: "global")))

  def test_a_reference_is_fetched_from_the_store_it_names
    assert_equal @reference, lookup.fetch(@reference).fetch(:uri)
  end

  def test_a_selected_passage_is_fetched_by_its_position
    assert_equal 1, lookup.selected(@reference, "1").fetch(:position)
  end

  def test_a_passage_that_is_not_a_number_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { lookup.selected(@reference, "first") }

    assert_equal "passage must be a positive integer", error.message
  end

  def test_an_unknown_store_is_refused_by_name
    error = assert_raises(Plastic::CLI::Scope::UnknownProject) { lookup.fetch("plastic://missing/1/spec.md") }

    assert_equal 'no project named "missing"', error.message
  end

  def test_a_store_that_needs_maintenance_is_not_read
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "other"))

    assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { lookup.fetch("plastic://other/1/spec.md") }
  end
end
