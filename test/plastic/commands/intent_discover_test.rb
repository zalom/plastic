# frozen_string_literal: true

require_relative "../../test_helper"

class IntentDiscoverTest < Plastic::TestCase
  def test_rejects_a_missing_or_unsafe_owning_intent_before_writing_a_manifest
    write_document("global", "global evidence")

    missing = plastic("intent", "discover", "99", "evidence", "--json", table: Plastic::CLI::TABLE)
    unsafe = plastic("intent", "discover", "../escape", "evidence", "--json", table: Plastic::CLI::TABLE)

    assert_equal 1, missing.code
    assert_equal 2, unsafe.code
    refute_path_exists store_path("discovery/99.json")
  end

  def test_records_deterministic_selected_source_candidates
    open_intent
    write_document("global", "global evidence")
    write_document("other", "other evidence")

    result = plastic("intent", "discover", "1", "evidence", "--source-project", "other", "--source-project", "global", "--json", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    document = JSON.parse(result.out)
    manifest = document.fetch("result").fetch("discovery")

    assert_discovery(manifest, result)
  end

  def test_hands_discovery_to_the_external_agent_through_a_routine
    open_intent
    write_document("global", "global evidence")

    result = plastic("intent", "discover", "1", "evidence", "--json", table: Plastic::CLI::TABLE)
    run = Plastic::Graph.open(home: @plastic_home, store: "global").retrieval.last_run("1")

    assert_equal 0, result.code
    assert_routine_handoff(run)
  end

  private

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
                 "architecture" => "external architecture provider records coverage and limitations", "context" => "plastic intent context 1 --from FILE --project global" }

    assert_equal expected, manifest.fetch("workflow")
  end

  def assert_persisted_manifest(manifest, result)
    assert_equal manifest, JSON.parse(File.read(store_path("discovery/1.json")))
    assert_equal "plastic intent context 1 --from FILE --project global", JSON.parse(result.out).fetch("next")
  end

  def write_document(store, body)
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin).write("1", "evidence.md", body)
    graphs.retrieval.backfill!
    graphs.retrieval.archived?("1")
  end
end
