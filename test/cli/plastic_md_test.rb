# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/cli"

class CliPlasticMdTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  PATH = File.join(ROOT, "PLASTIC.md")

  # RTK.md, the file this one is modelled on, is 452 bytes. A ceiling of 1,600
  # leaves room for the command list and the four rules, and nothing else: the
  # file is a pointer at the command line, never doctrine.
  CEILING_BYTES = 1_600

  def body
    @body ||= File.read(PATH)
  end

  def mentioned_commands
    body.scan(/`plastic ([a-z]+(?: [a-z]+)?)[^`]*`/).flatten.map(&:strip)
  end

  def test_the_file_exists
    assert_path_exists PATH
  end

  def test_the_file_stays_short
    assert_operator File.size(PATH), :<=, CEILING_BYTES,
      "PLASTIC.md is #{File.size(PATH)} bytes; the ceiling is #{CEILING_BYTES}"
  end

  def test_every_command_it_names_is_in_the_table
    unknown = mentioned_commands.reject do |name|
      Plastic::CLI::TABLE.key?(name) || Plastic::CLI::TABLE.key?(name.split.first)
    end

    assert_empty unknown, "PLASTIC.md names commands that do not exist: #{unknown.join(", ")}"
  end

  def test_it_names_at_least_the_three_commands_an_agent_starts_with
    %w[continue status help].each { |name| assert_includes mentioned_commands, name }
  end

  def test_it_says_that_a_next_line_is_to_be_followed
    assert_match(/next:/, body)
  end

  def test_it_says_what_exit_code_three_means
    assert_match(/exit code 3/i, body)
  end

  def test_it_carries_no_skill_names
    refute_match(/slash command|SKILL\.md/i, body)
  end
end
