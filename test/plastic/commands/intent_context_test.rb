# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "tempfile"

class IntentContextTest < Plastic::TestCase
  def test_validates_and_persists_agent_selected_evidence_without_writing_source_stores
    reference = write_document("other", "selected evidence")
    plastic("intent", "discover", "1", "selected", "--source-project", "other", table: Plastic::CLI::TABLE)
    before = File.binread(File.join(@plastic_home, "stores", "other", "knowledge_graph.db"))
    submission = { "evidence" => [reference], "facts" => ["a source fact"], "judgments" => ["an agent judgment"],
                   "architecture" => { "provider" => "external", "revision" => "abc", "coverage" => ["Ruby"], "limitations" => ["templates"] } }

    Tempfile.create(["context", ".json"]) do |file|
      file.write(JSON.generate(submission))
      file.flush
      submitted = plastic("intent", "context", "1", "--from", file.path, "--json", table: Plastic::CLI::TABLE)
      readback = plastic("intent", "context", "1", "--json", table: Plastic::CLI::TABLE)

      assert_equal 0, submitted.code
      assert_equal submission, JSON.parse(readback.out).fetch("result").fetch("context").slice("evidence", "facts", "judgments", "architecture")
    end
    assert_equal before, File.binread(File.join(@plastic_home, "stores", "other", "knowledge_graph.db"))
  end

  private

  def write_document(store, body)
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin).write("1", "evidence.md", body)
    graphs.retrieval.backfill!
    graphs.retrieval.reference("1", "evidence.md").fetch(:uri)
  end
end
