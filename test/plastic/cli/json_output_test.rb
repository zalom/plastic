# frozen_string_literal: true

require "json"
require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/status"
require_relative "../../../lib/plastic/commands/search"
require_relative "../../../lib/plastic/commands/node/claim"

class JsonOutputTest < Plastic::TestCase
  def setup
    super
    @out = StringIO.new
  end

  def output = Plastic::CLI::JsonOutput.new(out: @out, err: StringIO.new)

  def document = JSON.parse(@out.string)

  def test_a_project_with_no_next_step_prints_a_null_next
    output.row("id", "7").flush("b")

    assert_equal({ "result" => { "id" => "7" }, "next" => nil, "because" => nil }, document)
  end

  def test_keys_drop_the_colon_a_text_label_carries
    output.row("wrote:", ["a"]).flush

    assert_equal({ "wrote" => ["a"] }, document.fetch("result"))
  end

  def test_raw_lines_wait_under_output
    output.raw("line").row("id", "7").next_step("plastic next", because: "why").flush

    assert_equal({ "result" => { "id" => "7", "output" => ["line"] }, "next" => "plastic next", "because" => "why" }, document)
  end

  def test_json_is_on
    assert_predicate output, :json?
  end

  def test_an_error_prints_the_error_document
    output.failed("it broke")

    assert_equal({ "result" => { "error" => { "kind" => "failed", "message" => "it broke" } }, "next" => nil, "because" => "it broke" },
      document)
  end

  def test_usage_is_kind_usage
    output.usage("missing ID", "banner")

    assert_equal "usage", document.dig("result", "error", "kind")
  end

  def test_refused_is_kind_refused
    output.refused("owner")

    assert_equal "refused", document.dig("result", "error", "kind")
  end
end

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
