# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/doctor/codex_hook_command"

class DoctorCodexHookCommandTest < Plastic::TestCase
  def launcher(command) = Plastic::Doctor::CodexHookCommand.new(command, home: @home).launcher("Stop")

  def test_printing_a_hook_command_does_not_count_as_running_it
    assert_nil launcher("echo /tmp/bin/plastic hook stop")
  end

  def test_a_home_relative_launcher_resolves_under_the_injected_home
    assert_equal File.join(@home, ".plastic/bin/plastic"), launcher("~/.plastic/bin/plastic hook stop")
  end

  def test_extra_shell_commands_do_not_count_as_the_installed_hook
    assert_nil launcher("/tmp/bin/plastic hook stop ; echo done")
  end
end
