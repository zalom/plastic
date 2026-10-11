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

  def prose(page) = CommandReference::Markdown::Prose.lines(page.comment).first

  NO_CHAIN = ["hook end", "hook stop", "hook start", "graph resume", "project links", "project list", "status", "project new"].freeze

  def test_a_no_chain_page_names_the_command_call_and_never_says_before_the_chain
    NO_CHAIN.each do |words|
      body = text(words)

      refute_includes body, "Before the chain", words
      assert_includes body, "## The command", words
    end
  end

  def test_a_command_page_names_its_call_and_a_hook_page_names_its_respond
    assert_match(/The command's `call`, at \[`status\.rb:\d+`\]/, text("status"))
    assert_match(/The hook's `respond`, at \[`stop.rb:\d+`\]/, text("hook stop"))
    refute_includes text("hook stop"), "own `call`"
  end

  def test_a_routine_with_its_own_call_keeps_the_section_before_the_chain
    assert_includes text("update"), "## Before the chain"
  end

  def test_the_class_comment_is_skipped_when_it_repeats_the_summary_and_kept_when_it_adds_more
    status = page("status")
    sync = page("sync up")

    refute_includes text("status"), prose(status)
    refute_includes text("hook stop"), prose(page("hook stop"))
    assert_includes text("sync up"), prose(sync)
  end

  def test_the_ending_column_holds_words_and_never_raw_ruby
    CommandReferenceHelper.files.select { |path, _| path.end_with?("README.md") && path.include?("/commands/") }.each do |path, body|
      endings = body.split("## Outcomes").last.to_s

      refute_match(/\braise\b|next_step|CLI::|Command::|\bgate\b\(/, endings, path)
    end
  end

  def test_an_ending_says_its_kind_in_words_with_the_literal_message
    assert_includes text("backup list"), "Usage error: name the store with --store; --project does not apply"
    assert_includes text("project list"), "Offers the next command"
  end

  def test_the_own_call_section_shows_the_check_call_next_to_the_module_call
    body = text("backup restore")

    assert_includes body, "`check_call`"
    assert_includes body, "one_of(%i[timestamp latest]"
    refute_includes text("backup list"), "`check_call`, at"
  end
end
