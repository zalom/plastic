# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/document_get"
require "open3"
require "rbconfig"

class DocumentGetTest < Plastic::TestCase
  def get(*args) = plastic("document", "get", *args, table: Plastic::CLI::TABLE)

  def test_routed_help_prints_the_get_usage
    output, errors, status = Open3.capture3({ "HOME" => @home }, RbConfig.ruby, "bin/plastic", "help", "document", "get",
      chdir: File.expand_path("../../..", __dir__))

    assert_equal [0, ""], [status.exitstatus, errors]
    assert_includes output, "plastic document get REF"
    assert_includes output, "plastic://STORE/INTENT/PATH?revision=SHA256"
  end

  def test_prints_a_historical_qualified_document_as_structured_json
    writer = Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases.fetch(:knowledge), origin)
    writer.write("1", "plan.md", "first")
    reference = retrieval.reference("1", "plan.md").fetch(:uri)
    writer.write("1", "plan.md", "second")
    retrieval.backfill

    result = get(reference, "--json")

    assert_call result, code: 0, out: ["first", "revision"]
  end

  def test_plain_output_prints_readable_lines
    reference = write_document("global", "1", "plain.md", "first line\nsecond line")

    result = get(reference)

    assert_equal [0, ""], [result.code, result.err]
    refute_match(/\{|=>|\[/, result.out)
  end

  def test_reads_a_current_document_when_its_qualified_reference_omits_a_revision
    write_document("global", "1", "current.md", "current body")

    result = get("plastic://global/1/current.md", "--json")

    assert_call result, code: 0, out: /"body": "current body"/
  end

  def test_a_reference_to_an_unknown_store_fails
    assert_call get("plastic://unknown/1/plan.md"), code: 1, err: /project|maintenance/
  end

  def test_a_reference_to_a_missing_document_fails
    retrieval.backfill

    assert_call get("plastic://global/1/missing.md"), code: 1, err: /document/
  end

  def test_a_malformed_reference_is_a_usage_error_naming_it
    assert_call get("broken"), code: 2, err: /broken/
  end

  def test_a_bad_revision_or_an_undecodable_path_is_a_structured_usage_error
    write_document("global", "1", "long.md", "evidence")

    ["plastic://global/1/long.md?revision=bad", "plastic://global/1/%FF.md"].each do |invalid|
      assert_json_error(get(invalid, "--json"), 2, "usage")
    end
  end

  def test_a_passage_that_is_not_a_positive_number_is_a_structured_usage_error
    reference = write_document("global", "1", "long.md", "evidence " * 400)

    %w[word 0 -1].each { |position| assert_json_error(get(reference, "--passage", position, "--json"), 2, "usage") }
  end

  def test_a_passage_past_the_end_is_a_structured_failure
    reference = write_document("global", "1", "long.md", "evidence " * 400)

    assert_json_error(get(reference, "--passage", "99", "--json"), 1, "failed")
  end

  def test_a_passage_of_a_missing_document_is_a_structured_failure
    reference = write_document("global", "1", "long.md", "evidence")

    assert_json_error(get(reference.sub("long.md", "missing.md"), "--passage", "1", "--json"), 1, "failed")
  end

  private

  def write_document(store, intent_id, path, body)
    graphs = Plastic::Graph.create(home: @plastic_home, store:)
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:knowledge), origin).write(intent_id, path, body)
    graphs.retrieval.backfill
    graphs.retrieval.reference(intent_id, path).fetch(:uri)
  end

  def assert_json_error(result, code, kind)
    assert_equal code, result.code
    assert_equal kind, JSON.parse(result.out).dig("result", "error", "kind")
    refute_match(/(?:Traceback|NoMethodError|ArgumentError)/, "#{result.out}#{result.err}")
  end
end
