# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Hermetic structural tests asserting PLASTIC.md says git is a hard dependency and
# docs/help/agent-architecture.md documents the spawn preamble. Whitespace is
# normalized before matching so a test does not depend on exactly where a line
# is wrapped.
class PlasticMdPointerTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PLASTIC_MD = File.join(ROOT, "PLASTIC.md")
  # The spawn-preamble paragraph lives in docs/help/agent-architecture.md.
  ARCHITECTURE_REF = File.join(ROOT, "docs", "help", "agent-architecture.md")

  def normalized(path)
    File.read(path).gsub(/\s+/, " ")
  end

  def normalized_body
    normalized(PLASTIC_MD)
  end

  # --- spawn preamble carries live state + worktree cd-fallback -------

  def test_plastic_md_states_spawn_preamble_worktree_fallback
    body = normalized(ARCHITECTURE_REF)
    assert_match(/spawn preamble.*emits a live-state block purely from filesystem state/i, body,
                 "Agent Models and Dispatch must state the spawn preamble is a pure, filesystem-only live-state injection")
    assert_includes body,
      "appends the worktree's absolute path plus a verbatim instruction to `cd` there directly",
      "must state it appends the worktree's absolute path plus a cd-fallback instruction"
    assert_match(/EnterWorktree.*cannot discover a nested repo from a non-repo launch directory/, body,
                 "must state the EnterWorktree non-repo-launch-directory condition")
  end

  def test_plastic_md_says_git_is_a_hard_dependency
    assert_includes normalized_body, "git is a hard dependency"
  end
end
