# frozen_string_literal: true

require "json"
require_relative "../../test_helper"

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
