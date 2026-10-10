# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/plastic/harnesses"

class HarnessesTest < Plastic::TestCase
  def test_the_registry_names_claude_code_and_codex
    assert_equal %w[claude-code codex], Plastic::Harnesses.names
  end

  def test_each_entry_names_its_session_variables_process_and_settings_file
    claude = Plastic::Harnesses.fetch("claude-code")
    codex = Plastic::Harnesses.fetch("codex")

    assert_equal [["CLAUDE_CODE_SESSION_ID"], "claude", ".claude/settings.json"], [claude.session_variables, claude.process, claude.settings]
    assert_equal [%w[CODEX_THREAD_ID CODEX_SESSION_ID], "codex", ".codex/hooks.json"], [codex.session_variables, codex.process, codex.settings]
  end

  def test_each_entry_names_the_hook_command_of_each_event
    events = { "SessionStart" => "hook start", "Stop" => "hook stop", "SessionEnd" => "hook end" }

    assert_equal [events, events], Plastic::Harnesses.names.map { |name| Plastic::Harnesses.fetch(name).events }
  end

  def test_a_transcript_pattern_matches_its_own_harness_only
    claude = Plastic::Harnesses.fetch("claude-code").transcript
    codex = Plastic::Harnesses.fetch("codex").transcript

    assert_match Regexp.new(claude), "/u/.claude/projects/-u-app/s-1.jsonl"
    refute_match Regexp.new(claude), "/u/.codex/sessions/2026/10/11/rollout-1.jsonl"
    assert_match Regexp.new(codex), "/u/.codex/sessions/2026/10/11/rollout-1.jsonl"
  end

  def test_an_unregistered_name_is_a_usage_error_naming_the_registered_ones
    error = assert_raises(Plastic::CLI::Command::Usage) { Plastic::Harnesses.fetch("cursor") }

    assert_equal "no harness cursor; the registered harnesses are claude-code, codex", error.message
  end
end
