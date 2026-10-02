# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "tempfile"

class IntentContextTest < Plastic::TestCase
  def test_validates_and_persists_agent_selected_evidence_without_writing_source_stores
    open_intent
    reference = write_document("other", "selected evidence")
    plastic("intent", "discover", "1", "selected", "--source-project", "other", table: Plastic::CLI::TABLE)
    before = File.binread(File.join(@plastic_home, "stores", "other", "knowledge_graph.db"))
    submission = { "evidence" => [reference], "facts" => ["a source fact"], "interpretations" => ["an agent interpretation"],
                   "gaps" => ["a remaining gap"], "rulings" => ["an owner ruling"],
                   "architecture" => { "provider" => "external", "revision" => "abc", "coverage" => ["Ruby"], "limitations" => ["templates"] } }

    Tempfile.create(["context", ".json"]) do |file|
      file.write(JSON.generate(submission))
      file.flush
      submitted = plastic("intent", "context", "1", "--from", file.path, "--json", table: Plastic::CLI::TABLE)
      readback = plastic("intent", "context", "1", "--json", table: Plastic::CLI::TABLE)

      assert_equal 0, submitted.code
      assert_equal submission, JSON.parse(readback.out).fetch("result").fetch("context").slice("evidence", "facts", "interpretations", "gaps", "rulings", "architecture")
    end
    assert_equal before, File.binread(File.join(@plastic_home, "stores", "other", "knowledge_graph.db"))
  end

  def test_keeps_context_categories_separate_and_reports_changed_heads
    open_intent
    reference = write_document("other", "first selected evidence")
    plastic("intent", "discover", "1", "selected", "--source-project", "other", table: Plastic::CLI::TABLE)
    submission = {
      "evidence" => [reference],
      "facts" => ["The document has a selected passage."],
      "interpretations" => ["The agent considers it relevant."],
      "gaps" => ["No architecture receipt is available."],
      "rulings" => ["The owner chose lexical retrieval."],
      "architecture" => { "provider" => "external", "revision" => "abc", "coverage" => ["Ruby"], "limitations" => ["templates"] }
    }

    submit_context(submission)
    write_document("other", "second selected evidence")
    context = read_context

    assert_equal submission.slice("facts", "interpretations", "gaps", "rulings", "architecture"), context.slice("facts", "interpretations", "gaps", "rulings", "architecture")
    assert_equal [{ "uri" => reference, "state" => "stale" }], context.fetch("freshness").fetch("evidence")
  end

  private

  def write_document(store, body)
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin).write("1", "evidence.md", body)
    graphs.retrieval.backfill!
    graphs.retrieval.reference("1", "evidence.md").fetch(:uri)
  end

  def submit_context(submission)
    Tempfile.create(["context", ".json"]) do |file|
      file.write(JSON.generate(submission))
      file.flush
      result = plastic("intent", "context", "1", "--from", file.path, table: Plastic::CLI::TABLE)
      assert_equal 0, result.code
    end
  end

  def read_context
    result = plastic("intent", "context", "1", "--json", table: Plastic::CLI::TABLE)
    assert_equal 0, result.code
    JSON.parse(result.out).fetch("result").fetch("context")
  end
end
