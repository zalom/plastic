# frozen_string_literal: true

require_relative "whole_home"
require_relative "../../../scripts/lib/plastic/doctor"

class DoctorClaudeHooksTest < Plastic::TestCase
  include WholeHome

  REPAIR = "plastic install --claude --reinstall"

  def setup
    super
    whole_hooks
  end

  def checks = Plastic::Doctor::ClaudeHooks.new(settings_path, home: @home).checks

  def check(event) = checks.find { |item| item.label == "hook #{event}:" }

  def test_each_event_with_an_executable_plastic_file_is_ok
    assert_equal(["ok, plastic-resume"] * 3, checks.map(&:value))
  end

  def test_settings_that_are_not_json_are_one_finding
    write(settings_path, "{ not json")

    assert_equal [["hooks:", "#{settings_path} is not valid JSON", "fix the JSON in #{settings_path}, then run #{REPAIR}"]],
      checks.map(&:to_a)
  end

  def test_settings_that_hold_a_list_have_no_plastic_hook
    write(settings_path, "[]")

    assert_equal(["no Plastic hook"] * 3, checks.map(&:value))
  end

  def test_missing_settings_are_one_finding
    File.delete(settings_path)

    assert_equal [["hooks:", "#{settings_path} is missing", REPAIR]], checks.map(&:to_a)
  end

  def test_an_event_with_no_plastic_hook_is_a_finding
    write_hooks("SessionStart" => "\"#{hook_file}\"", "Stop" => "\"#{hook_file}\"", "SessionEnd" => "echo bye")

    assert_equal ["no Plastic hook", REPAIR], check("SessionEnd").to_h.values_at(:value, :repair)
  end

  def test_a_hook_file_that_is_gone_is_a_finding
    File.delete(hook_file)

    assert_equal "#{hook_file} is missing or not executable", check("Stop").value
  end

  def test_a_hook_file_that_is_not_executable_is_a_finding
    File.chmod(0o644, hook_file)

    assert_equal REPAIR, check("SessionStart").repair
  end

  def test_a_launcher_named_plastic_counts_as_a_plastic_hook
    launcher = File.join(@home, "bin", "plastic")
    write(launcher, "#!/bin/sh\n")
    File.chmod(0o755, launcher)
    write_hooks(Plastic::Hooks::Entries::EVENTS.to_h { |event, words| [event, "env -u RUBYOPT \"#{launcher}\" #{words} || true"] })

    assert_equal(["ok, plastic"] * 3, checks.map(&:value))
  end

  def test_a_path_from_the_home_folder_is_read_under_the_home
    write_hooks(Plastic::Hooks::Entries::EVENTS.keys.to_h { |event| [event, "~/.claude/hooks/plastic-resume"] })

    assert_empty checks.filter_map(&:repair)
  end
end
