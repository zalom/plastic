# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_rule"
require_relative "../../../scripts/lib/plastic/commands/status"

class ScopeBrokenProjectsTest < Plastic::TestCase
  def call(*args) = plastic("intent", "rule", *args, table: Plastic::CLI::TABLE)

  def projects(text) = File.write(File.join(@plastic_home, "projects.yml"), text)

  def test_a_broken_projects_file_fails_the_call_naming_the_file
    path = File.join(@plastic_home, "projects.yml")
    projects("plastic: [\n")

    result = call("1", "a ruling")

    assert_equal 1, result.code
    assert_includes result.err, path
  end

  def test_a_projects_file_with_no_projects_map_fails_the_call_naming_the_file
    path = File.join(@plastic_home, "projects.yml")
    projects("governing_docs: []\n")

    result = call("1", "a ruling")

    assert_equal 1, result.code
    assert_includes result.err, path
  end

  def test_a_broken_projects_file_fails_a_command_that_is_not_a_routine
    path = File.join(@plastic_home, "projects.yml")
    projects("plastic: [\n")

    result = plastic("status", table: Plastic::CLI::TABLE)

    assert_equal 1, result.code
    assert_includes result.err, path
    assert_equal "store:  global\n\nnext: plastic next\nbecause: pick the one to work on\n", result.out
  end
end
