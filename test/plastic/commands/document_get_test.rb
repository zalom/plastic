# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/document_get"
require_relative "../../../scripts/lib/plastic/commands/document_batch"
require "open3"
require "rbconfig"

class DocumentGetTest < Plastic::TestCase
  def test_routed_help_prints_document_command_usage
    %w[get batch].each do |command|
      output, errors, status = Open3.capture3(RbConfig.ruby, "bin/plastic", "help", "document", command, chdir: repository)

      assert_predicate status, :success?
      assert_empty errors
      assert_includes output, "plastic document #{command} REF"
      assert_includes output, "plastic://STORE/INTENT/PATH?revision=SHA256"
    end

    batch, = Open3.capture3(RbConfig.ruby, "bin/plastic", "help", "document", "batch", chdir: repository)

    assert_includes batch, "plastic document batch REF..."
  end

  def test_prints_a_historical_qualified_document_as_structured_json
    Plastic::Graph::EvidenceWriter.new(knowledge, origin).write("1", "plan.md", "first")
    reference = retrieval.reference("1", "plan.md").fetch(:uri)
    Plastic::Graph::EvidenceWriter.new(knowledge, origin).write("1", "plan.md", "second")
    retrieval.backfill!

    result = plastic("document", "get", reference, "--json", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_includes result.out, "first"
    assert_includes result.out, "revision"
  end

  def test_batch_routes_each_qualified_reference_to_its_selected_store_in_order
    first = write_document("global", "1", "global.md", "global")
    second = write_document("other", "2", "other.md", "other")
    third = write_document("third", "3", "third.md", "third")

    result = plastic("document", "batch", third, second, first, second, "--json", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_equal 4, result.out.scan('"store"').count { |entry| entry }
    assert_operator result.out.index("third"), :<, result.out.index("other")
    assert_operator result.out.index("other"), :<, result.out.index("global")
  end

  def test_refuses_malformed_unknown_and_missing_qualified_references
    %w[plastic://unknown/1/plan.md plastic://global/1/missing.md].each do |reference|
      result = plastic("document", "get", reference, table: Plastic::CLI::TABLE)

      assert_equal 1, result.code
      assert_match(/document|project|maintenance/, result.err)
    end

    malformed = plastic("document", "get", "broken", table: Plastic::CLI::TABLE)

    assert_equal 2, malformed.code
  end

  private

  def repository = File.expand_path("../../..", __dir__)

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def write_document(store, intent_id, path, body)
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin).write(intent_id, path, body)
    graphs.retrieval.backfill!
    graphs.retrieval.reference(intent_id, path).fetch(:uri)
  end
end
