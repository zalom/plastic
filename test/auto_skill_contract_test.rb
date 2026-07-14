# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

class AutoSkillContractTest < Minitest::Test
  SKILL = File.expand_path("../skills/auto/SKILL.md", __dir__)
  STARTING_SKILL = File.expand_path("../skills/intent-starting/SKILL.md", __dir__)

  def test_delegate_return_is_classified_before_the_next_handoff
    body = File.read(SKILL)

    assert_includes body, "Immediately after the specialist returns"
    assert_match(/before validating or dispatching\s+the next handoff/, body)
    assert_includes body, "--delegate <specialist-session-id> --status finished"
    assert_includes body, "--delegate <specialist-session-id> --status failed"
    assert_includes body, "finished` means the specialist returned a usable completion report"
    assert_includes body, "failed` means the specialist returned blocked, errored"
  end

  def test_boarding_snippets_pass_only_trusted_runtime_identity
    [SKILL, STARTING_SKILL].each do |path|
      body = File.read(path)
      assert_includes body, 'ENV["CODEX_THREAD_ID"].to_s.strip'
      assert_includes body, 'ENV["CLAUDE_CODE_SESSION_ID"].to_s.strip'
      assert_includes body, 'harness: harness, agent: "plastic-enforcer"'
      assert_includes body, 'thread: (!codex.empty? ? codex : nil)'
      assert_includes body, "Never"
      assert_match(/unknown/i, body)
    end
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
