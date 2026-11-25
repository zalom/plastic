# frozen_string_literal: true

require "tmpdir"
require_relative "../../../lib/plastic/installations/hook_entries"
require_relative "../../test_helpers/config_homes"
require_relative "../../../lib/plastic/config"
require_relative "../../test_helper"

class HookEntriesGuardTest < Minitest::Test
  include ConfigHomes

  COMMAND = "/opt/plastic/bin/plastic"

  def installed_groups
    Dir.mktmpdir do |dir|
      seed_config(dir, "")
      entries = Plastic::Installations::HookEntries.new(command: COMMAND, config: Plastic::Wiring.config(dir), launchers: {})
      [entries.claude({}), entries.codex({ "hooks" => {} })].map { |settings| settings.dig("hooks", "PreToolUse") }
    end
  end

  def test_claude_code_and_codex_run_the_guard_for_the_tools_that_write
    expected = [["Bash|Write|Edit|MultiEdit|NotebookEdit|apply_patch", %(env -u RUBYOPT "#{COMMAND}" hook guard || true)]]

    assert_equal [expected] * 2, installed_groups.map { |groups| groups.map { |group| [group["matcher"], group.dig("hooks", 0, "command")] } }
  end
end
