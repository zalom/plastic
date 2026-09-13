# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/harness_adapter"

# Structural test (intent 201, AC8): docs/reference/harness-adapters.md documents the
# skill-invocation prefix for each adapter. Modeled on
# test/plastic_md_batch0_conventions_test.rb's pattern: read the file, normalize
# whitespace, assert on its prose.
class HarnessAdaptersDocTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  DOC = File.join(ROOT, "docs", "reference", "harness-adapters.md")

  def normalized_body
    File.read(DOC).gsub(/\s+/, " ")
  end

  def test_documents_claude_slash_prefix
    body = normalized_body
    assert_includes body, "| Claude Code | `/plastic-<name>` (slash) |"
  end

  def test_documents_codex_dollar_prefix_and_implicit_selection
    body = normalized_body
    assert_includes body,
      "| Codex CLI | `$plastic-<name>` (dollar), explicit; Codex may also select a skill " \
      "implicitly by matching its `description` |"
  end

  # Intent 331a (X1): the engagement contract is late-capable now, not
  # chunk-0-only -- a chunk carrying an opener engages the message from that
  # chunk on, whatever its index.
  def test_documents_late_capable_engagement
    body = normalized_body
    assert_includes body, "engages the message from that chunk on, whatever its index"
  end

  # Intent 331a (X2): docs/internals.md documents the ScreenPaint registry.
  INTERNALS = File.join(ROOT, "docs", "internals.md")

  def test_internals_documents_the_screen_registry
    body = File.read(INTERNALS).gsub(/\s+/, " ")
    assert_includes body, "ScreenPaint.register"
    assert_includes body, "scripts/lib/screens/"
  end

  # Intent 331a1 (L9): the engagement contract names the decision marker
  # itself, and says explicitly when the launcher writes it.
  # L9b (post-execution review): the substring "PENDING" alone passes even
  # after the documented budget has rotted away from the code, so the numbers
  # D3 fixes and the staleness rule D2 fixes are pinned here too.
  def test_adapters_doc_names_pending_marker
    body = normalized_body
    assert_includes body, "PENDING"
    assert_includes body, "before Ruby boots"
    assert_includes body, "300 ms"
    assert_includes body, "20 ms"
    assert_includes body, "2 s"
    assert_match(/stale[^.]*PENDING[^.]*NOSCREEN/, body)
  end

  # --- Delivery watch (intent 340a, G7b, n4) ----------------------------------

  def test_documents_unattended_start_honestly
    body = normalized_body
    assert_includes body, "## Delivery watch"
    assert_includes body, "unattended continuation is delivered on both harnesses"
    assert_includes body, "unattended start"
    assert_includes body, "only where a Ruby loop owns dispatch"
    assert_includes body, "Codex"
    assert_includes body, "parked on Claude Code"
    assert_includes body, "Q6"
  end

  def test_unattended_start_sentence_matches_the_adapter
    body = normalized_body
    assert_includes body, HarnessAdapter::UNATTENDED_START_SENTENCE
  end

  def test_documents_the_watch_timer_per_harness
    body = normalized_body
    assert_includes body, "/loop"
    assert_includes body, "runner watch"
    assert_includes body, "SessionStart"
    assert_includes body, "--install-timer"
    assert_includes body, "launchctl"
    assert_includes body, "--dispatch --harness codex"
  end

  GUIDE = File.join(ROOT, "docs", "guides", "using-plastic-with-claude-code.md")

  def test_claude_code_guide_names_the_watch_loop
    body = File.read(GUIDE).gsub(/\s+/, " ")
    assert_includes body, "runner watch"
  end
end
