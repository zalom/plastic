# frozen_string_literal: true

require_relative "../../test_helper"

class ArchitectureStatusTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def test_status_tells_the_agent_to_check_the_map_and_offers_the_refresh
    result = cli("architecture", "status")

    assert_call result, code: 0,
      out: ["1. Check whether the project has an architecture map", "next: plastic architecture refresh"]
  end

  def test_each_call_hands_the_work_to_the_agent_again
    cli("architecture", "status")

    result = cli("architecture", "status")

    assert_call result, code: 0, out: ["1. Check whether the project has an architecture map"]
  end

  def test_help_lists_the_usage_line_and_the_shared_options
    result = cli("architecture", "status", "--help")

    assert_call result, code: 0, out: ["plastic architecture status", "--project SLUG"]
  end
end
