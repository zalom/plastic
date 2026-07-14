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
end
