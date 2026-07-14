# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Structural tests (intent 201, D5): the tutorial, the guides, and PLASTIC.md each name
# both the slash (Claude Code) and dollar (Codex) skill-invocation prefixes once, at the
# point invocation is first taught, with no forked Codex-only copy. Modeled on
# test/plastic_md_batch0_conventions_test.rb's pattern: read the file, normalize
# whitespace, assert on its prose.
class HarnessInvocationDocsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def normalized(path)
    File.read(File.join(ROOT, path)).gsub(/\s+/, " ")
  end

  def test_tutorial_skill_md_names_both_prefixes
    body = normalized("skills/tutorial/SKILL.md")
    assert_includes body, "`/plastic-update` first (`$plastic-update` on Codex)"
  end

  def test_track_1_names_both_prefixes
    body = normalized("skills/tutorial/references/track-1-guided.md")
    assert_includes body, "`/plastic-update` first (`$plastic-update` on Codex)"
  end

  def test_track_2_names_both_prefixes
    body = normalized("skills/tutorial/references/track-2-auto.md")
    assert_includes body, "`/plastic-update` first (`$plastic-update` on Codex)"
  end

  def test_track_3_names_both_prefixes
    body = normalized("skills/tutorial/references/track-3-projects-and-roadmaps.md")
    assert_includes body, "`/plastic-update` first (`$plastic-update` on Codex)"
  end

  def test_guides_index_names_both_prefixes
    body = normalized("docs/guides/index.md")
    assert_includes body, "On Codex CLI, invoke the same skill with a dollar prefix instead (`$plastic-<name>`)"
  end

  def test_what_the_gates_are_telling_you_names_both_prefixes
    body = normalized("docs/guides/what-the-gates-are-telling-you.md")
    assert_includes body, "On Codex CLI, invoke the same fix with a dollar prefix instead (for example `$plastic-doctor`)"
  end

  def test_plastic_md_names_both_prefixes_once
    body = normalized("PLASTIC.md")
    assert_includes body,
      "Codex CLI uses a dollar prefix instead (`$plastic-intent-creating`), and may also " \
      "select a skill implicitly by matching its description."
  end

  def test_plastic_md_feedback_bullet_no_longer_hardcodes_a_slash
    body = normalized("PLASTIC.md")
    assert_includes body, "offer to invoke the plastic-feedback skill yourself"
    refute_includes body, "offer to run `/plastic-feedback` yourself"
  end
end
