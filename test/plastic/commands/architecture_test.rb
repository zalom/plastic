# frozen_string_literal: true

require_relative "../../test_helper"
require "json"

class ArchitectureTest < Plastic::TestCase
  def test_reports_a_missing_architecture_snapshot_as_json_and_lists_its_refresh_command
    status = plastic("architecture", "status", "--json", table: Plastic::CLI::TABLE)
    help = plastic_bin("help", "architecture", "refresh")

    assert_equal 0, status.code, status.err
    assert_equal "missing", JSON.parse(status.out).dig("result", "architecture", "state")
    assert_includes help.out, "plastic architecture refresh"
  end
end
