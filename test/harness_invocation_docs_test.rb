# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Structural tests (intent 201, D5): the tutorial, the guides, and PLASTIC.md each name
# both the slash (Claude Code) and dollar (Codex) skill-invocation prefixes once, at the
# point invocation is first taught, with no forked Codex-only copy. Modeled on
# test/plastic_md_batch0_conventions_test.rb's pattern: read the file, normalize
# whitespace, assert on its prose.
class HarnessInvocationDocsTest < Minitest::Test
  # Intent 363 emptied PLASTIC.md of doctrine. It is now a one-page pointer at the
  # `plastic` command line (ruling D43), so the content pins that used to live here
  # were deleted rather than rewritten. The doctrine they guarded is still in the
  # conventions skill and its reference chapters, which Batch 2 rehomes into the
  # commands that need it.

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

  def test_reading_the_ledgers_names_both_prefixes
    body = normalized("docs/guides/reading-the-ledgers.md")
    assert_includes body, "On Codex CLI, invoke the same skill with a dollar prefix instead (for example `$plastic-doctor`)"
  end
end
