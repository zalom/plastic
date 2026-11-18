# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../../lib/plastic/installations/hook_entries"
require_relative "../../test_helper"
require_relative "../../support/child_process"

# The shell lines the installer writes into a harness, run against a stand-in command that fails.
class HookEntriesHookLineTest < Minitest::Test
  def failing_command(home)
    File.join(home, "plastic").tap do |path|
      File.write(path, "#!/bin/sh\nexit 2\n")
      File.chmod(0o755, path)
    end
  end

  def written_hook_lines(command)
    hooks = Plastic::Installations::HookEntries.new(command: command, config: nil, launchers: {}).codex({})["hooks"]
    hooks.values.flatten.flat_map { |group| group["hooks"].map { |hook| hook["command"] } }
  end

  def test_every_hook_line_the_installer_writes_exits_zero_when_the_call_fails
    Dir.mktmpdir do |home|
      lines = written_hook_lines(failing_command(home))

      assert_equal Plastic::Harnesses::EVENTS.size, lines.size
      lines.each do |line|
        assert ChildProcess.system(line, chdir: home), "#{line} did not exit zero"
      end
    end
  end
end
