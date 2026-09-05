# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

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
  def test_adapters_doc_names_pending_marker
    body = normalized_body
    assert_includes body, "PENDING"
    assert_includes body, "before Ruby boots"
  end
end
