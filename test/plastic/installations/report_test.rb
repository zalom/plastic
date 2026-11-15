# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/report"

# The hooks an install keeps and names as the person's own: a hook is named by its own file name, not
# by a folder of its path.
class ReportTest < Plastic::TestCase
  def hooks_running(*commands) = { "Stop" => [{ "hooks" => commands.map { |command| { "command" => command } } }] }

  def test_a_hook_whose_own_name_has_the_reserved_prefix_is_named
    assert_equal ["~/.claude/hooks/plastic-mine"], Plastic::Installations::Report.kept_names(hooks_running("~/.claude/hooks/plastic-mine"))
  end

  def test_a_hook_in_a_folder_with_the_reserved_prefix_is_left_alone
    assert_empty Plastic::Installations::Report.kept_names(hooks_running("/home/me/plastic-tools/my-hook", "ruby /work/plastic-notes/gate.rb"))
  end
end
