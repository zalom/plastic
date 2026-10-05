# frozen_string_literal: true

require_relative "../../../test_helper"

class CommandArgumentTest < Plastic::TestCase
  def argument(rest: false, optional: false)
    Plastic::CLI::Command::Argument.new(name: :id, label: "ID", text: "the intent", rest:, optional:)
  end

  def test_the_usage_marks_a_rest_argument_and_an_optional_one
    assert_equal ["ID", "ID...", "[ID]", "[ID...]"],
      [argument, argument(rest: true), argument(optional: true), argument(rest: true, optional: true)].map(&:usage)
  end

  def test_read_takes_the_word_at_its_index
    assert_equal "b", argument.read(%w[a b], 1)
  end

  def test_a_rest_argument_joins_every_word_left
    assert_equal "b c", argument(rest: true).read(%w[a b c], 1)
  end

  def test_a_missing_optional_argument_is_nil
    assert_nil argument(optional: true).read(["a"], 1)
  end

  def test_a_blank_required_argument_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { argument.read(["  "], 0) }

    assert_equal "missing ID", error.message
  end
end
