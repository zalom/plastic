# frozen_string_literal: true

require "json"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/installation_health"
require_relative "../../../scripts/lib/plastic/workflows/installation_hooks"

class InstallationHooksTest < Plastic::TestCase
  ACTIVE = "/share/active/bin/plastic"

  def settings(text) = File.join(FileUtils.mkdir_p(File.join(@home, ".claude")).first, "settings.json").tap { |file| File.write(file, text) }

  def hooks_for(*launchers)
    commands = launchers.map { |launcher| { "type" => "command", "command" => "\"#{launcher}\" hook resume" } }
    settings(JSON.generate("hooks" => { "SessionStart" => [{ "hooks" => commands }] }))
  end

  def check = Plastic::Workflows::InstallationHooks.new(home: @home, active: ACTIVE).check.to_h.values_at(:value, :repair)

  def test_no_settings_file_registers_no_hook
    assert_equal ["none registered", nil], check
  end

  def test_hooks_on_the_active_launcher_pass
    hooks_for(ACTIVE)

    assert_equal ["point at the active release", nil], check
  end

  def test_a_hook_on_another_launcher_names_it_and_the_reinstall
    hooks_for(ACTIVE, "/old/bin/plastic")

    assert_equal ["point at /old/bin/plastic", Plastic::Workflows::InstallationHooks::REINSTALL], check
  end

  def test_settings_that_do_not_parse_name_the_file_to_fix
    file = settings("{ broken")

    assert_equal ["#{file} is not valid JSON", "fix #{file} by hand"], check
  end

  def test_unreadable_names_the_settings_file_that_does_not_parse
    file = settings("{ broken")

    assert_equal file, Plastic::Workflows::InstallationHooks.new(home: @home).unreadable
  end

  def test_unreadable_is_nil_when_every_file_parses
    hooks_for(ACTIVE)

    assert_nil Plastic::Workflows::InstallationHooks.new(home: @home).unreadable
  end
end
