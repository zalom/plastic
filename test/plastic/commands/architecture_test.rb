# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/architecture_status"
require "json"

class ArchitectureTest < Plastic::TestCase
  def test_reports_a_missing_architecture_snapshot_as_json_and_lists_its_refresh_command
    status = plastic("architecture", "status", "--json", table: Plastic::CLI::TABLE)
    help = plastic("architecture", "refresh", "--help", table: Plastic::CLI::TABLE)

    assert_equal 0, status.code, status.err
    assert_equal "missing", JSON.parse(status.out).dig("result", "architecture", "state")
    assert_includes help.out, "plastic architecture refresh"
  end

  def test_marks_a_second_dirty_worktree_edit_as_stale
    command = freshness_command(current: { "state" => "fresh", "revision" => "abc" },
      saved: { "revision" => "abc", "worktree_hash" => "first" }, worktree_hash: "second")

    assert_equal "stale", command.send(:receipt).fetch("state")
  end

  private

  def freshness_command(current:, saved:, worktree_hash:)
    command_class = Class.new(Plastic::Commands::ArchitectureStatus) do
      define_method(:current_receipt) { current }
      define_method(:stored_receipt) { saved }
      define_method(:worktree_hash) { worktree_hash }
    end
    command_class.new([], words: "architecture status", environment: environment)
  end
end
