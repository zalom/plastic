# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/hook_purge"

class HookPurgeTest < Plastic::TestCase
  HookPurge = Plastic::Installations::HookPurge

  def purge(hooks) = HookPurge.new(:claude_purge_command?).call(hooks)

  def test_a_nested_and_a_bare_plastic_entry_are_removed_and_named_with_their_events
    hooks = {
      "Stop" => [{ "hooks" => [{ "command" => "plastic-record" }, { "command" => "mine" }] }, { "command" => "plastic-stop" }, { "command" => "keep" }],
      "Idle" => [{ "hooks" => [{ "command" => "plastic-record" }] }]
    }

    assert_equal [%w[Stop plastic-record], %w[Stop plastic-stop], %w[Idle plastic-record]], purge(hooks)
    assert_equal({ "Stop" => [{ "hooks" => [{ "command" => "mine" }] }, { "command" => "keep" }], "Idle" => [] }, hooks)
  end

  def test_a_value_that_is_not_a_list_or_a_group_is_left_alone
    hooks = { "Odd" => "text", "Stop" => ["text", { "other" => 1 }] }

    assert_equal [[], { "Odd" => "text", "Stop" => ["text", { "other" => 1 }] }], [purge(hooks), hooks]
  end
end
