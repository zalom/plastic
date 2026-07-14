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
end
