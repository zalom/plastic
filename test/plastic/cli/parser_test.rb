# frozen_string_literal: true

require_relative "../../test_helper"

class ParserTest < Plastic::TestCase
  Command = Plastic::CLI::Command

  def parser(arguments: [Command::Argument.new(:id, "ID", "the intent", false, false)],
    options: [Command::Option.new(:dir, "--dir DIR", "where", "/default", false, false)])
    Plastic::CLI::Parser.new(arguments:, options:, banner: "plastic x ID")
  end

  def test_an_option_takes_its_default
    assert_equal({ dir: "/default", id: "7" }, parser.parse(%w[7]))
  end

  def test_an_option_takes_its_value
    assert_equal "/d", parser.parse(%w[7 --dir /d])[:dir]
  end

  def test_json_and_project_belong_to_every_command
    values = parser.parse(%w[7 --json --project plastic])

    assert_equal [true, "plastic"], values.values_at(:json, :project)
  end

  def test_a_rest_argument_takes_every_word_left
    rest = [Command::Argument.new(:text, "TEXT", "words", true, false)]

    assert_equal "one two three", parser(arguments: rest, options: []).parse(%w[one two three])[:text]
  end

  def test_a_rest_argument_past_the_words_is_missing
    arguments = [Command::Argument.new(:id, "ID", "the intent", false, true),
      Command::Argument.new(:text, "TEXT", "words", true, true)]

    assert_nil parser(arguments:, options: []).parse([])[:text]
  end

  def test_an_optional_argument_may_be_missing
    optional = [Command::Argument.new(:id, "ID", "the intent", false, true)]

    assert_nil parser(arguments: optional, options: []).parse([])[:id]
  end

  def test_a_missing_argument_is_a_usage_error
    error = assert_raises(Command::Usage) { parser.parse([]) }

    assert_equal "missing ID", error.message
  end

  def test_a_blank_argument_counts_as_missing
    assert_raises(Command::Usage) { parser.parse([" "]) }
  end

  def test_an_extra_word_is_a_usage_error
    error = assert_raises(Command::Usage) { parser.parse(%w[7 8]) }

    assert_equal "unexpected 8", error.message
  end

  def test_an_unknown_switch_is_a_parse_error
    assert_raises(OptionParser::InvalidOption) { parser.parse(%w[7 --nope]) }
  end
end
