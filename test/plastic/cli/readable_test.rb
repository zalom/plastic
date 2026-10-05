# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/cli/readable"

class CLIReadableTest < Minitest::Test
  def test_a_hash_reads_as_key_value_lines
    assert_equal ["a: 1", "b: two"], Plastic::CLI::Readable.lines({ "a" => 1, "b" => "two" })
  end

  def test_a_nested_value_is_indented_under_its_key
    assert_equal ["a:", "  b: 1"], Plastic::CLI::Readable.lines({ "a" => { "b" => 1 } })
  end

  def test_a_list_item_starts_with_a_dash_and_its_continuation_is_indented
    assert_equal ["- a: 1", "  b: 2"], Plastic::CLI::Readable.lines([{ "a" => 1, "b" => 2 }])
  end

  def test_an_empty_item_in_a_list_keeps_its_dash
    assert_equal ["- a: 1", "- "], Plastic::CLI::Readable.lines([{ "a" => 1 }, ""])
  end
end
