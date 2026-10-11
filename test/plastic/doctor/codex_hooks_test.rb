# frozen_string_literal: true

require_relative "codex_home"
require_relative "../../../scripts/lib/plastic/doctor"

class DoctorCodexHooksTest < Plastic::TestCase
  include CodexHome

  def setup
    super
    whole_codex
  end

  def checks = Plastic::Doctor::CodexHooks.new(codex_hooks_path, home: @home).checks

  def check(event) = checks.find { |item| item.label == "hook #{event}:" }

  def test_current_installer_entries_pass
    assert_empty checks.filter_map(&:repair)
  end

  def test_a_quoted_launcher_path_with_spaces_passes
    @plastic_home = File.join(@home, "Plastic home")
    write(codex_launcher, "#!/bin/sh\n")
    File.chmod(0o755, codex_launcher)
    codex_hooks

    assert_empty checks.filter_map(&:repair)
  end

  def test_missing_hooks_name_the_reinstall
    File.delete(codex_hooks_path)

    assert_equal "plastic install --reinstall", checks.first.repair
  end

  def test_invalid_json_names_the_file_edit_before_reinstall
    write(codex_hooks_path, "{broken")

    assert_includes checks.first.repair, "fix the JSON"
  end

  def test_malformed_groups_are_findings_instead_of_exceptions
    write(codex_hooks_path, JSON.generate("hooks" => { "Stop" => [nil, "bad", { "hooks" => [false] }] }))

    assert_equal 3, checks.filter_map(&:repair).size
  end

  def test_a_non_map_document_is_a_finding
    write(codex_hooks_path, "[]")

    assert_includes checks.first.value, "map"
  end

  def test_a_hook_with_the_former_harness_option_does_not_pass
    change_codex_hook("Stop") { |hook| hook["command"].sub!("hook stop", "hook record --harness codex") }

    assert_equal "plastic install --reinstall", check("Stop").repair
  end

  def test_a_retired_dispatcher_does_not_pass
    change_codex_hook("Stop") { |hook| hook["command"] = "#{codex_launcher} record" }

    assert_equal "plastic install --reinstall", check("Stop").repair
  end

  def test_a_command_for_a_different_event_does_not_pass
    change_codex_hook("SessionEnd") { |hook| hook["command"].sub!("hook end", "hook stop") }

    assert_equal "plastic install --reinstall", check("SessionEnd").repair
  end

  def test_a_missing_launcher_is_a_finding
    File.delete(codex_launcher)

    assert_includes check("SessionStart").value, "missing or not executable"
  end

  def test_a_launcher_without_execute_permission_is_a_finding
    File.chmod(0o644, codex_launcher)

    assert_includes check("Stop").value, "missing or not executable"
  end

  def test_a_non_command_hook_does_not_pass
    change_codex_hook("Stop") { |hook| hook["type"] = "prompt" }

    refute_nil check("Stop").repair
  end

  def test_an_unmatched_shell_quote_is_a_finding
    change_codex_hook("Stop") { |hook| hook["command"] = '"unterminated' }

    refute_nil check("Stop").repair
  end
end
