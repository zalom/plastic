# frozen_string_literal: true

require "json"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/status"
require_relative "../../../scripts/lib/plastic/commands/search"
require_relative "../../../scripts/lib/plastic/commands/node_claim"

class JsonShapeTest < Plastic::TestCase
  def call(*args) = plastic(*args, "--json", table: Plastic::CLI::TABLE)

  def test_a_failed_call_writes_one_json_document_and_nothing_to_stderr
    result = call("node", "claim", "9", "n1")

    assert_equal [1, ""], [result.code, result.err]
    assert_equal "failed", JSON.parse(result.out).dig("result", "error", "kind")
  end

  def test_a_usage_error_writes_one_json_document_and_nothing_to_stderr
    result = call("node", "claim")

    assert_equal [2, ""], [result.code, result.err]
    assert_equal "usage", JSON.parse(result.out).dig("result", "error", "kind")
  end

  def test_a_refusal_writes_one_json_document_and_nothing_to_stderr
    out = StringIO.new
    err = StringIO.new
    Plastic::CLI::JsonOutput.new(out:, err:).refused("the owner holds it")

    assert_equal "", err.string
    assert_equal "refused", JSON.parse(out.string).dig("result", "error", "kind")
  end

  def test_status_puts_its_rows_under_result_rows_as_data
    open_keyed_intent
    rows = JSON.parse(call("status").out).dig("result", "rows")

    assert_kind_of Array, rows
    assert_includes rows.flat_map(&:keys), "store"
  end

  def test_a_text_error_still_writes_its_line_to_stderr
    result = plastic("node", "claim", "9", "n1", table: Plastic::CLI::TABLE)

    assert_match(/\Aplastic: /, result.err)
  end
end
