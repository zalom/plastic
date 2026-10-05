# frozen_string_literal: true

require "optparse"
require_relative "../../../test_helper"

class CommandOptionTest < Plastic::TestCase
  def option(repeatable: false, required: false)
    Plastic::CLI::Command::Option.new(name: :tag, switch: "--tag TAG", text: "a tag", default: repeatable ? [] : nil, repeatable:, required:)
  end

  def parse(option, argv)
    values = { tag: option.default }
    parser = OptionParser.new
    option.add_to(parser, values)
    parser.parse(argv)
    values[:tag]
  end

  def test_the_usage_brackets_an_optional_switch_only
    assert_equal ["[--tag TAG]", "--tag TAG"], [option.usage, option(required: true).usage]
  end

  def test_a_switch_given_twice_keeps_the_last_value
    assert_equal "b", parse(option, %w[--tag a --tag b])
  end

  def test_a_repeatable_switch_keeps_every_value
    assert_equal %w[a b], parse(option(repeatable: true), %w[--tag a --tag b])
  end

  def test_a_repeatable_switch_leaves_its_default_list_empty
    repeatable = option(repeatable: true)
    parse(repeatable, %w[--tag a])

    assert_empty repeatable.default
  end
end
