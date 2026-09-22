# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

# Intent 316a1, O2: docs/reference/harness-adapters.md has no intent-screen
# page at all before this intent (grep -rln "intent screen\|MessageDisplay\|
# IntentScreenAnsi" docs/ returns nothing), so this is a new section, not an
# edit. Modeled on test/harness_support_docs_test.rb's pattern: read the
# file, slice by heading, assert on the prose.
class HarnessCoreAdapterDocsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  ADAPTERS_DOC = File.join(ROOT, "docs", "reference", "harness-adapters.md")

  def adapters_doc_text
    File.read(ADAPTERS_DOC)
  end

  def core_adapter_section
    text = adapters_doc_text
    start = text.index("## The harness-agnostic core and the Claude adapter")
    raise "core/adapter heading not found" unless start
    rest = text[start..]
    next_heading = rest.index("\n## ", 1)
    next_heading ? rest[0...next_heading] : rest
  end

  def test_doc_carries_the_new_section
    assert_includes adapters_doc_text, "## The harness-agnostic core and the Claude adapter"
  end

  def test_section_names_every_core_and_adapter_file
    section = core_adapter_section
    %w[
      scripts/lib/intent_screen.rb
      scripts/lib/intent_screen_ansi.rb
      scripts/intent-screen
      scripts/lib/message_display.rb
      scripts/hook-message-display
      hooks/message-display
    ].each do |path|
      assert_includes section, path, "expected the section to name #{path}"
    end
  end

  def test_section_carries_both_exact_phrases
    section = core_adapter_section
    assert_includes section, "Harness-agnostic core: no harness assumption lives here."
    assert_includes section, "Claude adapter: Claude Code only; the core is harness-agnostic."
  end

  def test_section_states_the_markdown_safe_default_and_supersession
    section = core_adapter_section.gsub(/\s+/, " ")
    assert_includes section, "markdown_safe:"
    assert_includes section, "defaulting to `false`"
    assert_includes section, "316a's D6"
  end
end
