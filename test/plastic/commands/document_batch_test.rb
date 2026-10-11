# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/document_batch"
require_relative "../../support/child_process"
require "rbconfig"

class DocumentBatchTest < Plastic::TestCase
  def test_routed_help_prints_the_batch_usage
    output, errors, status = ChildProcess.capture3({ "HOME" => @home }, RbConfig.ruby, "bin/plastic", "help", "document", "batch",
      chdir: File.expand_path("../../..", __dir__))

    assert_equal [0, ""], [status.exitstatus, errors]
    assert_includes output, "plastic document batch REF..."
    assert_includes output, "plastic://STORE/INTENT/PATH?revision=SHA256"
  end

  def test_batch_routes_each_qualified_reference_to_its_selected_store_in_order
    first = write_document("global", "1", "global.md", "global")
    second = write_document("other", "2", "other.md", "other")
    third = write_document("third", "3", "third.md", "third")

    result = plastic("document", "batch", third, second, first, second, "--json", table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: /third.*other.*global.*other/m
    assert_equal 4, result.out.scan('"store"').size
  end

  def test_plain_output_prints_readable_lines
    first = write_document("global", "1", "global.md", "global")
    second = write_document("other", "2", "other.md", "other")

    result = plastic("document", "batch", first, second, table: Plastic::CLI::TABLE)

    assert_equal [0, ""], [result.code, result.err]
    refute_match(/\{|=>|\[/, result.out)
  end

  def test_batch_fails_on_a_missing_reference_with_exit_1
    write_document("global", "1", "present.md", "here")
    result = plastic("document", "batch", "plastic://global/1/missing.md", table: Plastic::CLI::TABLE)

    assert_call result, code: 1, err: /document/
  end

  private

  def write_document(store, intent_id, path, body)
    graphs = Plastic::Graph.create(home: @plastic_home, store:)
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:knowledge), origin).write(intent_id, path, body)
    graphs.retrieval.backfill
    graphs.retrieval.reference(intent_id, path).fetch(:uri)
  end
end
