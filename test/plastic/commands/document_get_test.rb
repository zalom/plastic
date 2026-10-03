# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/document_get"
require_relative "../../../scripts/lib/plastic/commands/document_batch"
require "open3"
require "rbconfig"

class DocumentGetTest < Plastic::TestCase
  def test_routed_help_prints_document_command_usage
    %w[get batch].each { |command| assert_document_help(command) }
  end

  def test_prints_a_historical_qualified_document_as_structured_json
    assert_historical_document(historical_document_result)
  end

  def test_reads_a_current_document_when_its_qualified_reference_omits_a_revision
    write_document("global", "1", "current.md", "current body")

    result = plastic("document", "get", "plastic://global/1/current.md", "--json", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code, result.err
    assert_equal "current body", JSON.parse(result.out).dig("result", "document", "body")
  end

  def test_batch_routes_each_qualified_reference_to_its_selected_store_in_order
    assert_batch_order(batch_result)
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

  def test_reports_reference_and_passage_validation_as_structured_errors
    reference = write_document("global", "1", "long.md", "evidence " * 400)

    assert_invalid_references
    assert_invalid_passages(reference)
  end

  private

  def repository = File.expand_path("../../..", __dir__)

  def knowledge = store_graphs.databases.fetch(:knowledge)

  def write_document(store, intent_id, path, body)
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin).write(intent_id, path, body)
    graphs.retrieval.backfill
    graphs.retrieval.reference(intent_id, path).fetch(:uri)
  end

  def assert_json_error(result, code, kind)
    assert_equal code, result.code
    document = JSON.parse(result.out)

    assert_equal kind, document.fetch("result").fetch("error").fetch("kind")
    refute_match(/(?:Traceback|NoMethodError|ArgumentError)/, "#{result.out}#{result.err}")
  end

  def assert_document_help(command)
    output, errors, status = Open3.capture3({ "HOME" => @home }, RbConfig.ruby, "bin/plastic", "help", "document", command, chdir: repository)

    assert_predicate status, :success?
    assert_empty errors
    assert_includes output, "plastic document #{command} REF"
    assert_includes output, "plastic://STORE/INTENT/PATH?revision=SHA256"
    assert_includes output, "plastic document batch REF..." if command == "batch"
  end

  def historical_document_result
    writer = Plastic::Graph::EvidenceWriter.new(knowledge, origin)
    writer.write("1", "plan.md", "first")
    reference = retrieval.reference("1", "plan.md").fetch(:uri)
    writer.write("1", "plan.md", "second")
    retrieval.backfill
    plastic("document", "get", reference, "--json", table: Plastic::CLI::TABLE)
  end

  def assert_historical_document(result)
    assert_equal 0, result.code
    assert_includes result.out, "first"
    assert_includes result.out, "revision"
  end

  def batch_result
    first = write_document("global", "1", "global.md", "global")
    second = write_document("other", "2", "other.md", "other")
    third = write_document("third", "3", "third.md", "third")
    plastic("document", "batch", third, second, first, second, "--json", table: Plastic::CLI::TABLE)
  end

  def assert_batch_order(result)
    assert_equal 0, result.code
    assert_equal 4, result.out.scan('"store"').count { |entry| entry }
    assert_operator result.out.index("third"), :<, result.out.index("other")
    assert_operator result.out.index("other"), :<, result.out.index("global")
  end

  def assert_invalid_references
    ["plastic://global/1/long.md?revision=bad", "plastic://global/1/%FF.md"].each do |invalid|
      assert_json_error(plastic("document", "get", invalid, "--json", table: Plastic::CLI::TABLE), 2, "usage")
    end
  end

  def assert_invalid_passages(reference)
    %w[word 0 -1].each do |position|
      assert_json_error(plastic("document", "get", reference, "--passage", position, "--json", table: Plastic::CLI::TABLE), 2, "usage")
    end
    assert_json_error(plastic("document", "get", reference, "--passage", "99", "--json", table: Plastic::CLI::TABLE), 1, "failed")
    missing = reference.sub("long.md", "missing.md")

    assert_json_error(plastic("document", "get", missing, "--passage", "1", "--json", table: Plastic::CLI::TABLE), 1, "failed")
  end
end
