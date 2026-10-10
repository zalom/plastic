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

  def test_an_entry_that_still_names_record_end_is_drift_with_its_repair
    write_hooks("SessionStart" => "\"#{hook_file}\" hook resume", "Stop" => "\"#{hook_file}\" hook record",
      "SessionEnd" => "\"#{hook_file}\" hook record --end")

    assert_equal ["names the retired hook record --end", REPAIR], check("SessionEnd").to_h.values_at(:value, :repair)
  end

  def test_a_current_end_entry_is_not_drift
    write_hooks("SessionStart" => "\"#{hook_file}\" hook resume", "Stop" => "\"#{hook_file}\" hook record",
      "SessionEnd" => "\"#{hook_file}\" hook end")

    assert_nil check("SessionEnd").repair
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
    write_hooks(Plastic::Hooks::Entries::EVENTS.to_h { |event, words| [event, "env -u RUBYOPT \"#{launcher}\" #{format(words, "claude-code")} || true"] })

    assert_equal(["ok, plastic"] * 3, checks.map(&:value))
  end

  def test_a_launcher_whose_end_entry_still_names_a_harness_is_drift_with_its_repair
    write_hooks(launcher_lines.merge("SessionEnd" => "\"#{plastic_launcher}\" hook end --harness claude-code"))

    assert_equal ["names the stale command line hook end --harness claude-code", REPAIR], check("SessionEnd").to_h.values_at(:value, :repair)
  end

  def test_a_launcher_whose_resume_entry_names_no_harness_is_drift
    write_hooks(launcher_lines.merge("SessionStart" => "\"#{plastic_launcher}\" hook resume"))

    assert_equal REPAIR, check("SessionStart").repair
  end

  def plastic_launcher
    File.join(@home, "bin", "plastic").tap do |launcher|
      write(launcher, "#!/bin/sh\n")
      File.chmod(0o755, launcher)
    end
  end

  def launcher_lines = Plastic::Hooks::Entries::EVENTS.to_h { |event, words| [event, "\"#{plastic_launcher}\" #{format(words, "claude-code")}"] }

  def test_a_path_from_the_home_folder_is_read_under_the_home
    write_hooks(Plastic::Hooks::Entries::EVENTS.keys.to_h { |event| [event, "~/.claude/hooks/plastic-resume"] })

    assert_empty checks.filter_map(&:repair)
  end
end
