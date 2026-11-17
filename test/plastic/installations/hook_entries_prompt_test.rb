# frozen_string_literal: true

require "tmpdir"
require_relative "../../../lib/plastic/installations/hook_entries"
require_relative "../../test_helpers/config_homes"
require_relative "../../../lib/plastic/config"
require_relative "../../test_helper"

class HookEntriesPromptTest < Minitest::Test
  include ConfigHomes

  COMMAND = "/opt/plastic/bin/plastic"

  def commands_for(hooks, event) = Array(hooks[event]).flat_map { |group| group["hooks"].map { |hook| hook["command"] } }

  def installed_commands
    Dir.mktmpdir do |dir|
      seed_config(dir, "")
      entries = Plastic::Installations::HookEntries.new(command: COMMAND, config: Plastic::Wiring.config(dir), launchers: {})
      [entries.claude({}), entries.codex({ "hooks" => {} })].map { |settings| commands_for(settings["hooks"], "UserPromptSubmit") }
    end
  end

  def test_installs_the_prompt_event_for_claude_code_and_codex
    assert_equal [[%(env -u RUBYOPT "#{COMMAND}" hook prompt || true)]] * 2, installed_commands
  end
end
