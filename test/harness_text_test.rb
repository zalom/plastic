# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/harness_text"

# Intent 239: the Codex install-time text transform. Pure String to String, no IO.
class HarnessTextTest < Minitest::Test
  NAMES = %w[auto conventions dashboard doctor intent-creating intent-continuing
             uninstall].freeze

  def codex(text, rel_path: "auto/SKILL.md")
    HarnessText.for_codex(text, rel_path: rel_path, skill_names: NAMES)
  end

  def test_plugin_root_becomes_home
    assert_equal "$HOME/.plastic/scripts/new-intent", codex('${CLAUDE_PLUGIN_ROOT}/scripts/new-intent')
  end

  def test_plugin_root_is_not_a_tilde
    refute_includes codex('${CLAUDE_PLUGIN_ROOT}/scripts/new-intent'), "~/.plastic"
  end

  def test_template_path
    assert_equal "from $HOME/.plastic/templates/outcome.md.",
      codex('from ${CLAUDE_PLUGIN_ROOT}/templates/outcome.md.')
  end

  def test_skills_root
    assert_equal "- all `~/.agents/skills/plastic-*/` skills",
      codex("- all `~/.claude/skills/plastic-*/` skills")
  end

  def test_state_dir
    assert_equal "`~/.agents/plastic/manifest.json`",
      codex("`~/.claude/plastic/manifest.json`")
  end

  def test_settings_file
    assert_equal "grep -n plastic ~/.codex/hooks.json",
      codex("grep -n plastic ~/.claude/settings.json")
  end

  def test_hooks_dir_left_alone
    text = "ls ~/.claude/hooks  | grep '^plastic-'"
    assert_equal text, codex(text)
  end

  def test_slash_prefix
    assert_equal "Run $plastic-doctor now.", codex("Run /plastic-doctor now.")
  end

  def test_unknown_name_left_alone
    text = "a stale lock names /plastic-lock"
    assert_equal text, codex(text)
  end

  def test_relative_path_left_alone
    text = "Read `../plastic-conventions/references/x.md`"
    assert_equal text, codex(text)
  end

  def test_tmp_path_left_alone
    text = "`/tmp/plastic-{session}.json` is the hot cache"
    assert_equal text, codex(text)
  end

  def test_glob_path_left_alone
    text = "agents/plastic-*.md role files"
    assert_equal text, codex(text)
  end

  def test_claude_hook_path_left_alone
    text = "- ~/.claude/hooks/plastic-session-start"
    assert_equal text, codex(text)
  end

  def test_longest_name_wins
    assert_equal "$plastic-intent-continuing", codex("/plastic-intent-continuing")
  end

  def test_no_trailing_hyphen_bleed
    text = "/plastic-doctor-x"
    assert_equal text, codex(text)
  end

  def test_rule_order_pinned
    names = NAMES + ["dashboard"]
    input    = "Run /plastic-doctor, read ~/.claude/skills/plastic-dashboard/templates/x.md, " \
               "then \"${CLAUDE_PLUGIN_ROOT}/scripts/new-intent\"."
    expected = "Run $plastic-doctor, read ~/.agents/skills/plastic-dashboard/templates/x.md, " \
               "then \"$HOME/.plastic/scripts/new-intent\"."
    assert_equal expected, HarnessText.for_codex(input, rel_path: "auto/SKILL.md", skill_names: names)
  end
end
