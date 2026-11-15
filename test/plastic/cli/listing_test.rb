# frozen_string_literal: true

require "json"
require_relative "../../test_helper"

# plastic help: the core commands first, then one heading for each family.
class CLIListingTest < Plastic::TestCase
  def help(*words) = plastic_bin("help", *words, table: Plastic::CLI::TABLE)

  def test_help_prints_the_core_commands_before_the_first_family_heading
    lines = help.out.lines(chomp: true)
    before = lines.first(lines.index("intent:") || 0)

    assert_equal [true, true], [before.any? { |line| line.start_with?("doctor") }, before.none? { |line| line.include?("intent new") }]
  end

  def test_help_prints_one_heading_for_each_family_but_core
    headings = help.out.lines(chomp: true).grep(/\A[a-z]+:\z/)

    assert_equal Plastic::CLI::FAMILIES.keys.drop(1).map { |family| "#{family}:" }, headings
  end

  def test_help_prints_every_command_once
    out = help.out

    Plastic::CLI::TABLE.each_key { |words| assert_equal 1, out.lines.count { |line| line.strip.start_with?("#{words} ") }, words }
  end

  def test_help_json_is_a_list_of_families_each_with_its_commands
    result = JSON.parse(help("--json").out).fetch("result")
    row = result.find { |entry| entry["family"] == "intent" }.fetch("commands").find { |entry| entry["command"] == "intent new" }

    assert_equal [Plastic::CLI::FAMILIES.keys, { "command" => "intent new", "summary" => Plastic::CLI::TABLE.fetch("intent new").last }],
      [result.map { |entry| entry.fetch("family") }, row]
  end

  def test_help_with_a_family_word_lists_that_family_only
    call = help("intent")

    assert_equal [0, ""], [call.code, call.err]
    assert_includes call.out, "intent new"
    refute_includes call.out, "node claim"
    refute_includes call.out, "doctor"
  end

  def test_help_config_lists_the_config_family
    out = help("config").out

    assert_includes out, "config set"
    assert_includes out, "config list"
  end

  def test_help_with_a_command_of_two_words_still_prints_its_usage
    assert_equal "plastic sync down [--overwrite [PATH]] [--merge] [--dry-run]", help("sync", "down").out.lines.first.chomp
  end
end
