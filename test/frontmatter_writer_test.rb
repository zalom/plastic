# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../scripts/lib/frontmatter_writer"

# ACTION 2 — pure style-preserving frontmatter writer tests. No file IO.
class FrontmatterWriterTest < Minitest::Test
  FLOW = <<~MD
    ---
    id: "11"
    intent: Fix regressions
    sources: ["global:24"]
    chain: []
    created: 2026-06-08
    author: human
    tags: [plastic, npm]
    ---

    ## Intent
    Body content.

    ## Links
    - keep me untouched
  MD

  # Mixed: block-style sources, flow-style chain in the SAME file (the real 1a2).
  MIXED = <<~MD
    ---
    id: '1a2'
    intent: Build the app
    sources:
    - '1a'
    - '1'
    chain: ["knowdb:1"]
    created: 2026-05-24
    author: human
    tags:
    - reddit
    - rails
    ---

    ## Intent
    Body.
  MD

  def test_flow_sources_rewritten_in_place
    out = FrontmatterWriter.rewrite_arrays(FLOW, sources: ["22c"], chain: [])
    assert_includes out, "sources: [\"22c\"]"
    assert_includes out, "chain: []"
  end

  def test_flow_other_keys_and_body_byte_identical
    out = FrontmatterWriter.rewrite_arrays(FLOW, sources: ["22c"], chain: [])
    %w[id: intent: created: author:].each { |k| assert_includes out, FLOW.lines.find { |l| l.start_with?(k) } }
    assert_includes out, "tags: [plastic, npm]"
    assert_includes out, "## Links\n- keep me untouched"
    assert_includes out, "## Intent\nBody content."
  end

  def test_unchanged_arrays_return_identical_content
    out = FrontmatterWriter.rewrite_arrays(FLOW, sources: ["global:24"], chain: [])
    assert_equal FLOW, out
  end

  def test_block_style_sources_preserved
    out = FrontmatterWriter.rewrite_arrays(MIXED, sources: %w[19a 1], chain: ["knowdb:1"])
    # block style retained: separate `- '..'` lines with single quotes
    assert_includes out, "sources:\n- '19a'\n- '1'\n"
    # flow chain untouched
    assert_includes out, "chain: [\"knowdb:1\"]"
  end

  def test_block_style_other_keys_and_body_untouched
    out = FrontmatterWriter.rewrite_arrays(MIXED, sources: %w[19a 1], chain: ["knowdb:1"])
    assert_includes out, "id: '1a2'"
    assert_includes out, "tags:\n- reddit\n- rails\n"
    assert_includes out, "## Intent\nBody."
  end

  def test_block_style_unchanged_returns_identical
    out = FrontmatterWriter.rewrite_arrays(MIXED, sources: %w[1a 1], chain: ["knowdb:1"])
    assert_equal MIXED, out
  end

  def test_no_frontmatter_returns_content_unchanged
    plain = "no frontmatter here\n"
    assert_equal plain, FrontmatterWriter.rewrite_arrays(plain, sources: ["x"], chain: [])
  end
end
