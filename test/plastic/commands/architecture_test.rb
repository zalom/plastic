# frozen_string_literal: true

require_relative "../../test_helper"

class ArchitectureTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def test_status_tells_the_agent_to_check_the_map_and_offers_the_refresh
    result = cli("architecture", "status")

    assert_equal 0, result.code, result.err
    assert_includes result.out, "1. Check whether the project has an architecture map"
    assert_includes result.out, "next: plastic architecture refresh"
  end

  def test_refresh_tells_the_agent_to_regenerate_the_map
    result = cli("architecture", "refresh")

    assert_equal 0, result.code, result.err
    assert_includes result.out, "1. Regenerate the project's architecture map"
    assert_includes result.out, "next: none"
  end

  def test_each_call_hands_the_work_to_the_agent_again
    cli("architecture", "status")

    result = cli("architecture", "status")

    assert_equal 0, result.code, result.err
    assert_includes result.out, "1. Check whether the project has an architecture map"
  end
end
