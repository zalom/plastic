# frozen_string_literal: true

require_relative "../../test_helper"

module DiscoveryDocuments
  def write_document(store, body)
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:knowledge), origin).write("1", "evidence.md", body)
    graphs.retrieval.backfill
    graphs.retrieval.archived?("1")
  end
end

class IntentDiscoverTest < Plastic::TestCase
  include DiscoveryDocuments

  def test_replaces_malformed_or_incomplete_saved_context_with_a_fresh_external_handoff
    open_intent
    write_document("other", "selected evidence")
    source = File.join(@plastic_home, "stores", "other", "knowledge_graph.db")
    before = File.binread(source)

    contexts = ["not-json", "{}", JSON.generate("discovery" => { "query" => "evidence 2", "scope" => ["global"] })]
    contexts.each_with_index do |data, index|
      write_saved_context(data)

      assert_fresh_discovery("evidence #{index}")
    end

    assert_equal before, File.binread(source)
  end

  def test_rejects_a_missing_owning_intent_before_writing_a_manifest
    write_document("global", "global evidence")

    missing = plastic("intent", "discover", "99", "evidence", "--json", table: Plastic::CLI::TABLE)

    assert_call missing, code: 1, out: ["code_discover_retrieval, gate: no intent 99 in owning store"],
      err: "plastic: code_discover_retrieval, gate: no intent 99 in owning store\n"
    refute_path_exists store_path("discovery/99.json")
  end

  def test_rejects_an_unsafe_owning_intent_as_usage
    assert_call plastic("intent", "discover", "../escape", "evidence", "--json", table: Plastic::CLI::TABLE), code: 2, out: ['"kind": "usage"', 'invalid intent id \"../escape\"'], err: /invalid intent id "\.\.\/escape"/
  end

  def test_refuses_unknown_or_unmaintained_source_stores_without_recreating_them
    open_intent
    write_document("other", "selected evidence")
    missing = File.join(@plastic_home, "stores", "other", "work_graph.db")
    File.delete(missing)
    File.write(File.join(@plastic_home, "stores", "missing"), "not a store directory")

    unknown = plastic("intent", "discover", "1", "evidence", "--source-project", "missing", table: Plastic::CLI::TABLE)
    unmaintained = plastic("intent", "discover", "1", "evidence", "--source-project", "other", table: Plastic::CLI::TABLE)

    assert_discovery_failure(unknown, "unknown source projects: missing")
    assert_discovery_failure(unmaintained, "retrieval maintenance is required before source other can be read")
    refute_path_exists missing
  end

  def test_records_deterministic_selected_source_candidates
    open_intent
    write_document("global", "global evidence")
    write_document("other", "other evidence")

    result = plastic("intent", "discover", "1", "evidence", "--source-project", "other", "--source-project", "global", "--json", table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [result.code, result.err]
    assert_discovery(JSON.parse(result.out).dig("result", "discovery"), result)
  end

  def test_hands_discovery_to_the_external_agent_through_a_routine
    open_intent
    write_document("global", "global evidence")

    result = plastic("intent", "discover", "1", "evidence", "--json", table: Plastic::CLI::TABLE)
    run = Plastic::Graph.open(home: @plastic_home, store: "global").retrieval.last_run("1")

    assert_equal [0, ""], [result.code, result.err]
    assert_routine_handoff(run)
    assert_equal "evidence", JSON.parse(result.out).dig("result", "discovery", "query")
  end

  private

  def assert_fresh_discovery(query)
    result = plastic("intent", "discover", "1", query, "--source-project", "other", "--json", table: Plastic::CLI::TABLE)
    document = JSON.parse(result.out)

    assert_equal 0, result.code, result.err
    assert_equal "plastic intent context 1 --from FILE --project global", document.fetch("next")
    assert_equal query, document.dig("result", "discovery", "query")
  end

  def assert_discovery_failure(result, message)
    assert_call result, code: 1, err: [message]
  end

  def assert_routine_handoff(run)
    assert_equal "handed_off", run.status
    assert_equal :agent_external_agent_workflow, run.at
    assert_equal "1", run.facts.fetch(:intent_id)
    assert_equal "evidence", run.facts.fetch(:terms)
  end

  def assert_discovery(manifest, result)
    assert_equal "1", manifest.fetch("intent_id")
    assert_equal "evidence", manifest.fetch("query")
    assert_equal %w[global other], manifest.fetch("scope")
    assert_equal %w[global other], manifest.fetch("candidates").map { |candidate| candidate.fetch("store") }
    assert_candidates(manifest)
    assert_workflow(manifest)
    assert_persisted_manifest(manifest, result)
  end

  def assert_candidates(manifest)
    assert manifest.fetch("candidates").all? { |candidate| candidate.key?("uri") && candidate.key?("revision") && candidate.key?("archived") }
  end

  def assert_workflow(manifest)
    expected = { "search" => "plastic search evidence --source-project global --source-project other", "evidence" => "plastic document get REF",
                 "context" => "plastic intent context 1 --from FILE --project global" }

    assert_equal expected, manifest.fetch("workflow")
  end

  def assert_persisted_manifest(manifest, result)
    assert_equal manifest, JSON.parse(File.read(store_path("discovery/1.json")))
    assert_equal "plastic intent context 1 --from FILE --project global", JSON.parse(result.out).fetch("next")
  end

  def write_saved_context(data)
    Plastic::Graph.open(home: @plastic_home, store: "global").databases.fetch(:knowledge).transaction do |batch|
      batch.put(:retrieval_contexts, { intent_id: "1", data:, updated_at: STAMP })
    end
  end
end

class IntentDiscoverOutputTest < Plastic::TestCase
  include DiscoveryDocuments

  def test_plain_output_prints_readable_lines
    open_intent
    write_document("global", "global evidence")

    result = plastic("intent", "discover", "1", "evidence", table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [result.code, result.err]
    refute_match(/\{|=>|\[/, result.out)
  end
end
