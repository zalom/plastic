# frozen_string_literal: true

require_relative "../../test_helper"

class ArchitectureRefreshTest < Plastic::TestCase
  def test_refresh_tells_the_agent_to_regenerate_the_map
    result = plastic("architecture", "refresh", table: Plastic::CLI::TABLE)

    assert_call result, code: 0, out: ["1. Regenerate the project's architecture map", "because:"]
  end
end
