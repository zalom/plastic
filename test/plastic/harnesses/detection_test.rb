# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/harnesses/detection"

class HarnessDetectionTest < Plastic::TestCase
  Ancestry = Data.define(:ancestors)

  def detect(event: {}, env: {}, ancestors: [])
    Plastic::Harnesses::Detection.new(event:, env:, processes: Ancestry.new(ancestors:)).harness
  end

  def test_a_harness_field_on_the_event_names_it
    assert_equal "codex", detect(event: { harness: "codex" }, env: { "CLAUDE_CODE_SESSION_ID" => "s-1" })
  end

  def test_a_field_only_codex_writes_names_codex
    assert_equal "codex", detect(event: { session_id: "s-1", turn_id: "t-1" }, env: { "CLAUDE_CODE_SESSION_ID" => "c-0" })
  end

  def test_codex_inside_a_claude_code_shell_is_named_by_its_own_session_variable
    env = { "CLAUDE_CODE_SESSION_ID" => "c-0", "CODEX_THREAD_ID" => "x-1" }

    assert_equal "codex", detect(event: { session_id: "x-1" }, env:)
  end

  def test_claude_code_inside_a_codex_shell_is_named_by_its_own_session_variable
    env = { "CLAUDE_CODE_SESSION_ID" => "c-1", "CODEX_THREAD_ID" => "x-0" }

    assert_equal "claude-code", detect(event: { session_id: "c-1" }, env:)
  end

  def test_a_transcript_path_no_harness_declares_names_no_harness
    assert_equal "unknown", detect(event: { session_id: "h-1", transcript_path: "/u/.hermes/sessions/h-1.jsonl" }, env: {})
  end

  def test_the_transcript_path_names_the_harness
    assert_equal "claude-code", detect(event: { session_id: "c-1", transcript_path: "/u/.claude/projects/-u/c-1.jsonl" }, env: { "CODEX_THREAD_ID" => "x-0" })
  end

  def test_the_nearest_ancestor_process_names_the_harness
    assert_equal "codex", detect(event: { session_id: "s-1" }, ancestors: %w[zsh codex claude])
  end

  def test_an_agent_variable_names_a_harness_the_registry_lacks
    assert_equal "cursor", detect(event: { session_id: "s-1" }, env: { "AI_AGENT" => "cursor" })
  end

  def test_an_agent_variable_with_a_registered_name_is_not_trusted
    assert_equal "unknown", detect(event: { session_id: "s-1" }, env: { "AI_AGENT" => "codex" })
  end

  def test_with_nothing_to_go_on_the_harness_is_unknown
    assert_equal "unknown", detect(event: { session_id: "s-1" })
  end

  def test_an_unregistered_harness_field_is_passed_over
    assert_equal "unknown", detect(event: { session_id: "s-1", harness: "nope" })
  end
end
