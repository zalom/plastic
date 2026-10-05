# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/retrieval/context/freshness"

class RetrievalContextEvidenceTest < Plastic::TestCase
  def setup
    super
    @intent = open_intent
    @reference = retrieval.reference("1", @intent.file).fetch(:uri)
  end

  def state(document = {}, reference: @reference)
    Plastic::Graph::Retrieval::Context::Evidence.new(document:, reference:, retrieval:).state
  end

  def rewrite = Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases[:knowledge], origin).write("1", @intent.file, "changed")

  def archive = store_graphs.databases[:work].transaction { |batch| batch.put(:archives, { intent_id: "1", at: STAMP }) }

  def test_a_reference_to_the_current_revision_is_fresh
    assert_equal({ "uri" => @reference, "state" => "fresh", "archived" => false }, state)
  end

  def test_a_reference_to_an_older_revision_is_stale
    rewrite

    assert_equal "stale", state.fetch("state")
  end

  def test_an_intent_archived_since_the_save_is_stale
    archive

    assert_equal [true, "stale"], state({ "archive_states" => { @reference => false } }).values_at("archived", "state")
  end

  def test_an_archive_state_saved_with_the_reference_stays_fresh
    archive

    assert_equal "fresh", state({ "archive_states" => { @reference => true } }).fetch("state")
  end

  def test_a_reference_with_no_revision_never_matches_the_current_one
    assert_equal "stale", state(reference: "plastic://global/1/#{@intent.file}").fetch("state")
  end
end
