# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../scripts/lib/links_section"
require_relative "../scripts/lib/intent_validator"

# ACTION 2 — pure LinksSection body-rewriter tests. Hermetic in-memory strings, no
# file IO. Proves replace-in-place, insert-at-canonical-position, idempotency, the
# preserved trailing-newline shape, and (load-bearing) the NEGATIVE guarantee that
# frontmatter and every non-Links section stay byte-identical across a rewrite.
class LinksSectionTest < Minitest::Test
  FM = <<~FM
    ---
    id: "1"
    intent: "Test intent"
    sources: ["2"]
    chain: ["3"]
    created: 2026-06-01
    author: test
    tags: [t]
    ---
  FM

  SECTION = "## Links\n- [[2--two|Two]]\n- [[3--three|Three]]\n"

  def multi_section_file(links_block)
    FM + "\n" \
      "# Title\n\n" \
      "## Intent\nThe intent body.\n\n" \
      "## Context\nThe context body.\n\n" \
      "## Outcome\nThe outcome body.\n\n" \
      "## Insights\nThe insights body.\n\n" \
      "#{links_block}"
  end

  def test_replace_legacy_placeholder_block
    legacy = "## Links\n\n<!-- Retroactive (intent 60b): relationships live in the frontmatter. -->\n"
    content = multi_section_file(legacy)
    out = LinksSection.rewrite(content, SECTION)
    assert_includes out, SECTION
    refute_includes out, "Retroactive (intent 60b)"
    assert_equal 1, out.scan("## Links").size, "heading appears exactly once"
  end

  def test_replace_adhoc_prose_block
    prose = "## Links\n- [[2]] some hand-written note\n- bare mention\n"
    content = multi_section_file(prose)
    out = LinksSection.rewrite(content, SECTION)
    assert_includes out, SECTION
    refute_includes out, "hand-written note"
  end

  def test_insert_when_no_links_section
    no_links = FM + "\n# Title\n\n## Intent\nBody.\n\n## Context\nCtx.\n\n## Outcome\nOut.\n\n## Insights\nIns.\n"
    out = LinksSection.rewrite(no_links, SECTION)
    assert_includes out, SECTION
    # Body now validates: Links present, no unknown sections.
    body = IntentValidator.body_of(out)
    result = IntentValidator.validate_sections(body)
    assert result[:ok], "rewritten body must have the sanctioned sections: #{result.inspect}"
  end

  # Load-bearing NEGATIVE test: every byte outside the `## Links` section is
  # identical before and after the rewrite. We slice the pre-Links region (the
  # frontmatter + all earlier sections) from both and assert equality.
  def test_only_links_section_changes
    before = multi_section_file("## Links\n- [[9]] stale\n")
    after = LinksSection.rewrite(before, SECTION)

    # Frontmatter byte-identical.
    assert_equal FM, after[0, FM.length]

    # Everything up to the `## Links` heading is byte-identical in both.
    pre_before = before[0...before.index("## Links")]
    pre_after = after[0...after.index("## Links")]
    assert_equal pre_before, pre_after, "all content before ## Links must be byte-identical"

    # Each non-Links section body survives verbatim.
    %w[Intent Context Outcome Insights].each do |s|
      assert_includes after, "## #{s}\nThe #{s.downcase} body.\n"
    end
  end

  def test_idempotent_rewrite_is_noop
    content = multi_section_file(SECTION)
    once = LinksSection.rewrite(content, SECTION)
    twice = LinksSection.rewrite(once, SECTION)
    assert_equal once, twice, "second rewrite over projected content is a no-op"
  end

  def test_idempotent_returns_input_object_when_unchanged
    content = multi_section_file(SECTION)
    out = LinksSection.rewrite(content, SECTION)
    # Already canonical: rewriting again returns the input unchanged.
    assert_equal content, LinksSection.rewrite(content, SECTION) if out == content
  end

  def test_trailing_newline_preserved
    content = multi_section_file(SECTION)
    out = LinksSection.rewrite(content, SECTION)
    assert out.end_with?("\n"), "trailing newline shape preserved"
  end

  def test_links_as_last_section_replaced_in_place
    # When Links is the final section (the canonical position), replacement ends
    # the body and re-running is byte-stable.
    content = multi_section_file("## Links\n- [[2]] old\n")
    out = LinksSection.rewrite(content, SECTION)
    assert out.end_with?(SECTION), "Links section ends the body when it is last"
  end
end
