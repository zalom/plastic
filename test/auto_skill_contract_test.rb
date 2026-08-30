# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

class AutoSkillContractTest < Minitest::Test
  SKILL = File.expand_path("../skills/auto/SKILL.md", __dir__)

  def test_delegate_return_is_classified_before_the_next_handoff
    body = File.read(SKILL)

    assert_includes body, "Immediately after the specialist returns"
    assert_match(/before validating or dispatching\s+the next handoff/, body)
    assert_includes body, "--delegate <specialist-session-id> --status finished"
    assert_includes body, "--delegate <specialist-session-id> --status failed"
    assert_includes body, "finished` means the specialist returned a usable completion report"
    assert_includes body, "failed` means the specialist returned blocked, errored"
  end

  # The arming snippet is a `plastic-lock arm` call (intent 307): it passes a
  # Codex thread as the session, the harness, and the thread only when
  # CODEX_THREAD_ID is set, a Claude session only when CLAUDE_CODE_SESSION_ID
  # is set, and nothing otherwise, so the CLI keys the lock by a derived key.
  def test_boarding_snippet_passes_only_trusted_runtime_identity
    body = File.read(SKILL)
    assert_includes body, "plastic-lock arm"
    assert_includes body, "--mode auto"
    assert_includes body, "--agent plastic-enforcer"
    assert_includes body, 'codex="${CODEX_THREAD_ID:-}"'
    assert_includes body, 'claude="${CLAUDE_CODE_SESSION_ID:-}"'
    assert_includes body, '--harness codex --session "$codex" --thread "$codex"'
    assert_includes body, '--harness claude --session "$claude"'
    assert_includes body, "Never guess identity from an absent runtime variable"
    assert_match(/unknown/i, body)
  end

  def test_delegate_snippets_carry_known_role_and_runtime_identity
    body = File.read(SKILL)
    assert_includes body, "--harness <specialist-harness-when-known>"
    assert_includes body, "--agent <role>"
    assert_includes body, "--model <resolved-model-when-known>"
    assert_includes body, "--thread <reported-CODEX_THREAD_ID-when-Codex>"
    assert_includes body, "--status finished --harness <same-specialist-harness-when-known>"
    assert_includes body, "--status failed --harness <same-specialist-harness-when-known>"
    assert_includes body, "Omit `--harness`, `--model`, or `--thread`"
  end
end
