# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/plastic/harnesses"

class HarnessesTest < Plastic::TestCase
  def test_the_registry_names_claude_code_codex_and_hermes
    assert_equal %w[claude-code codex hermes], Plastic::Harnesses.names
  end

  def test_each_entry_names_its_session_variables_process_and_settings_file
    claude = Plastic::Harnesses.fetch("claude-code")
    codex = Plastic::Harnesses.fetch("codex")

    assert_equal [["CLAUDE_CODE_SESSION_ID"], "claude", ".claude/settings.json"], [claude.session_variables, claude.process, claude.settings]
    assert_equal [%w[CODEX_THREAD_ID CODEX_SESSION_ID], "codex", ".codex/hooks.json"], [codex.session_variables, codex.process, codex.settings]
  end

  def test_each_entry_names_the_hook_command_of_each_event
    events = { "SessionStart" => "hook start", "Stop" => "hook stop", "SessionEnd" => "hook end" }

    assert_equal [events, events], %w[claude-code codex].map { |name| Plastic::Harnesses.fetch(name).events }
  end

  def test_hermes_declares_its_folder_and_installer_and_no_hook_events_or_detection_fields
    hermes = Plastic::Harnesses.fetch("hermes")

    assert_equal [".hermes", "hermes", {}, [], nil, nil, nil, nil], hermes.to_h.values_at(:folder, :installer, :events, :session_variables, :transcript, :process, :settings, :doctor)
  end

  def test_a_transcript_pattern_matches_its_own_harness_only
    claude = Plastic::Harnesses.fetch("claude-code").transcript
    codex = Plastic::Harnesses.fetch("codex").transcript

    assert_match Regexp.new(claude), "/u/.claude/projects/-u-app/s-1.jsonl"
    refute_match Regexp.new(claude), "/u/.codex/sessions/2026/10/11/rollout-1.jsonl"
    assert_match Regexp.new(codex), "/u/.codex/sessions/2026/10/11/rollout-1.jsonl"
  end

  def test_each_entry_names_the_installer_that_writes_into_it
    assert_equal %w[claude codex hermes], Plastic::Harnesses.all.map(&:installer)
  end

  def test_a_harness_whose_settings_folder_is_in_the_home_is_found
    FileUtils.mkdir_p(File.join(@home, ".codex"))

    assert_equal ["codex"], Plastic::Harnesses.found(home: @home, path: "").map(&:name)
  end

  def test_a_harness_whose_program_is_on_the_path_is_found
    bin = FileUtils.mkdir_p(File.join(@home, "bin")).first
    File.write(File.join(bin, "claude"), "#!/bin/sh\n")
    File.chmod(0o755, File.join(bin, "claude"))

    assert_equal ["claude-code"], Plastic::Harnesses.found(home: @home, path: "#{@home}/none:#{bin}").map(&:name)
  end

  def test_a_file_on_the_path_that_cannot_run_finds_no_harness
    bin = FileUtils.mkdir_p(File.join(@home, "bin")).first
    File.write(File.join(bin, "codex"), "")

    assert_empty Plastic::Harnesses.found(home: @home, path: bin)
  end

  def test_a_harness_that_names_no_program_is_found_by_its_folder_only
    bin = FileUtils.mkdir_p(File.join(@home, "bin")).first
    File.write(File.join(bin, "hermes"), "#!/bin/sh\n")
    File.chmod(0o755, File.join(bin, "hermes"))
    found = Plastic::Harnesses.found(home: @home, path: bin)
    FileUtils.mkdir_p(File.join(@home, ".hermes"))

    assert_equal [[], ["hermes"]], [found, Plastic::Harnesses.found(home: @home, path: bin).map(&:name)]
  end

  def test_with_neither_folder_nor_program_no_harness_is_found
    assert_empty Plastic::Harnesses.found(home: @home, path: "")
  end

  def test_an_unregistered_name_is_a_usage_error_naming_the_registered_ones
    error = assert_raises(Plastic::CLI::Command::Usage) { Plastic::Harnesses.fetch("cursor") }

    assert_equal "no harness cursor; the registered harnesses are claude-code, codex, hermes", error.message
  end
end
