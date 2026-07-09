# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Hermetic structural tests (intent 157) asserting PLASTIC.md documents the
# four Batch 0 conventions merged in v1.0.1 (intents 150, 151, 152, 154).
# Modeled on test/roadmap_test.rb's test_plastic_md_states_* pattern: read
# the file, assert on its prose. Whitespace is normalized before matching so
# a test does not depend on exactly where a line is wrapped.
class PlasticMdBatch0ConventionsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  PLASTIC_MD = File.join(ROOT, "PLASTIC.md")

  def normalized_body
    File.read(PLASTIC_MD).gsub(/\s+/, " ")
  end

  # --- 150: code-gate mirrors bash-gate's audited # plastic-ok escape -------

  def test_plastic_md_states_code_gate_escape_mirrors_bash_gate
    body = normalized_body
    assert_includes body,
      "The code gate (Write and Edit) carries the identical audited " \
      "`# plastic-ok` escape, logged to the same file.",
      "### The gates by name must state the code gate's mirrored # plastic-ok escape, scoped to Write and Edit"
    assert_match(/escape does not extend to.*NotebookEdit.*MCP structural edits/i, body,
                 "must state the escape does not extend to NotebookEdit or MCP structural edits (gated, but no escape hatch)")
  end

  # --- 152: spawn preamble carries live state + worktree cd-fallback -------

  def test_plastic_md_states_spawn_preamble_worktree_fallback
    body = normalized_body
    assert_match(/spawn preamble.*emits a live-state block purely from filesystem state/i, body,
                 "Agent Models and Dispatch must state the spawn preamble is a pure, filesystem-only live-state injection")
    assert_includes body,
      "appends the worktree's absolute path plus a verbatim instruction to `cd` there directly",
      "must state it appends the worktree's absolute path plus a cd-fallback instruction"
    assert_match(/EnterWorktree.*cannot discover a nested repo from a non-repo launch directory/, body,
                 "must state the EnterWorktree non-repo-launch-directory condition")
  end

  # --- 151: insight-append ships on every install and update ---------------

  def test_plastic_md_states_insight_append_ships_every_install
    assert_includes normalized_body,
      "which ships with every install and update, formats the prefix, validates it, and appends at the bottom.",
      "the insight-append paragraph must state the CLI ships with every install and update"
  end

  # --- 154: new-intent style-preserving chain wiring + quoting -------------

  def test_plastic_md_states_new_intent_quoting_and_chain_style
    body = normalized_body
    assert_includes body,
      "`--intent` text is escaped for double quotes and backslashes before it lands in frontmatter",
      "Rules for Skills rule 6 must state --intent text is safely escaped"
    assert_includes body,
      "a reciprocal `chain:` append preserves the target intent's existing flow- or block-style entries",
      "Rules for Skills rule 6 must state chain wiring preserves flow- or block-style entries"
  end
end
