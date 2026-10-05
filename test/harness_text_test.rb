# frozen_string_literal: true

require_relative "test_helper"
require "harness_text"

class HarnessTextTest < Plastic::TestCase
  def codex(text, skill_names: %w[intent intent-continuing])
    HarnessText.for_codex(text, rel_path: "skills/a/SKILL.md", skill_names:)
  end

  def test_the_plugin_root_becomes_the_plastic_home
    assert_equal '"$HOME/.plastic/scripts/x"', codex('"${CLAUDE_PLUGIN_ROOT}/scripts/x"')
  end

  def test_each_claude_root_maps_to_its_codex_root
    assert_equal "~/.agents/skills and ~/.codex/hooks.json", codex("~/.claude/skills and ~/.claude/settings.json")
  end

  def test_a_hooks_path_under_claude_is_left_alone
    assert_equal "~/.claude/hooks/plastic-intent", codex("~/.claude/hooks/plastic-intent")
  end

  def test_a_skill_call_takes_the_codex_prefix_and_the_longest_name_wins
    assert_equal "run $plastic-intent-continuing then $plastic-intent", codex("run /plastic-intent-continuing then /plastic-intent")
  end

  def test_a_name_that_is_not_an_installed_skill_keeps_its_slash
    assert_equal "/plastic-lock", codex("/plastic-lock")
  end

  def test_a_skill_name_inside_a_longer_path_keeps_its_slash
    assert_equal "../tmp/plastic-intent", codex("../tmp/plastic-intent")
  end

  def test_no_skill_names_leaves_the_text_unchanged
    assert_equal "/plastic-intent", HarnessText.rewrite_skill_prefix("/plastic-intent", [], "$")
  end
end
