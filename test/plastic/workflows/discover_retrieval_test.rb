# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/discover_retrieval"

class DiscoverRetrievalTest < Plastic::TestCase
  def discover(intent_id = "1") = run_workflow(Plastic::Workflows::DiscoverRetrieval, intent_id:, terms: "alpha", source_projects: [])

  def saved_discovery = store_graphs.databases[:knowledge].row("SELECT data FROM retrieval_discoveries WHERE intent_id = '1'")

  def save_context(data)
    store_graphs.databases[:knowledge].transaction { |batch| batch.put(:retrieval_contexts, { intent_id: "1", data:, updated_at: STAMP }) }
  end

  def test_the_discovery_is_recorded_and_reported
    open_intent

    outcome, context = discover

    assert_equal [:done, "alpha"], [outcome, JSON.parse(saved_discovery.fetch("data")).fetch("query")]
    assert_equal ["global"], printed_row(context, "discovery").fetch("scope")
  end

  def test_the_agent_is_told_how_to_submit_the_context
    open_intent

    _outcome, context = discover

    assert_equal "plastic intent context 1 --from FILE --project global", context.context_command
  end

  def test_a_saved_context_for_the_same_query_and_scope_is_complete
    open_intent
    save_context(JSON.generate("discovery" => { "query" => "alpha", "scope" => ["global"] }))

    assert discover.last.context_complete
  end

  def test_a_saved_context_that_does_not_parse_is_not_complete
    open_intent
    save_context("not json")

    refute discover.last.context_complete
  end

  def test_an_unknown_intent_fails_with_no_discovery
    outcome, = discover("9")

    assert_equal "code_discover_retrieval, gate: no intent 9 in owning store", outcome.message
    assert_nil saved_discovery
  end
end
