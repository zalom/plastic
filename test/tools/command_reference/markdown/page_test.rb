# frozen_string_literal: true

require_relative "../../../command_reference_helper"
require_relative "../../../docs_stale_words_guard_test"

class CommandReferenceMarkdownPageTest < Minitest::Test
  include CommandReferenceHelper

  def text(words) = CommandReference::Markdown::Page.new(page(words)).to_s

  def test_no_built_page_holds_a_stale_phrase
    CommandReferenceHelper.files.each do |path, body|
      assert_empty body.scan(DocsStaleWordsGuardTest::STALE), path
    end
  end

  def test_a_page_has_the_sections_a_reader_expects
    body = text("intent end")

    ["# plastic intent end", "## What it touches", "## How the call flows", "## Outcomes", "component.svg", "chain.svg"].each { |part| assert_includes body, part }
  end

  def test_the_outcomes_table_links_the_kernel_wide_endings_once
    assert_equal 1, text("intent end").scan("../../dsl/README.md#how-any-call-can-end").size
  end

  def test_the_page_does_not_repeat_what_the_drawing_shows
    refute_match(/It reads .* graph and writes/, text("intent end"))
  end

  def test_a_no_chain_page_has_no_chain_section_and_a_call_box
    body = text("project list")

    refute_includes body, "chain.svg"
    assert_includes body, "call.svg"
  end

  def test_the_outcomes_table_names_the_exit_and_the_code
    assert_includes text("intent end"), "| Ending | Exit | next: | Code |"
  end
end
