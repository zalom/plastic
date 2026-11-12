# frozen_string_literal: true

require_relative "../../../command_reference_helper"
require_relative "../../../docs_stale_words_guard_test"

class CommandReferenceMarkdownPageTest < Minitest::Test
  include CommandReferenceHelper

  SECTIONS = ["## Components", "## The events of one call", "## What one call reads, writes and prints", "## How a call ends", "## What the page leaves out"].freeze
  SHARED = "../../dsl/README.md#what-every-call-shares"
  OWN_CALL_PAGES = ["hook end", "hook stop", "hook start", "graph resume", "project links", "project list", "status", "project new", "config", "config list", "config get", "config set"].freeze

  def text(words) = CommandReference::Markdown::Page.new(page(words)).to_s

  def readmes = CommandReferenceHelper.files.select { |path, _| path.match?(%r{/commands/[^/]+/README\.md\z}) }

  def prose_lines(body) = body.gsub(/^```.*?^```\n/m, "")

  def test_no_built_page_holds_a_stale_phrase
    CommandReferenceHelper.files.each do |path, body|
      assert_empty body.scan(DocsStaleWordsGuardTest::STALE), path
    end
  end

  def test_every_command_page_has_the_six_sections_in_order
    assert_equal 76, readmes.size
    readmes.each do |path, body|
      headings = prose_lines(body).lines.grep(/^(?:# |## )/).map(&:chomp)

      assert_match(/\A# plastic /, headings.first, path)
      assert_equal SECTIONS, headings.drop(1), path
    end
  end

  def test_no_command_page_keeps_an_old_heading
    readmes.each do |path, body|
      ["What it touches", "How the call flows", "## Outcomes", "\n## The command", "Before the chain"].each { |old| refute_includes body, old, path }
    end
  end

  def test_a_page_has_the_sections_a_reader_expects
    body = text("intent end")

    ["# plastic intent end", *SECTIONS, "component.svg", "workflows.svg", "touches.svg"].each { |part| assert_includes body, part }
  end

  def test_the_outcomes_table_links_the_kernel_wide_endings_once
    assert_equal 1, text("intent end").scan("../../dsl/README.md#how-any-call-can-end").size
  end

  def test_the_page_does_not_repeat_what_the_drawing_shows
    refute_match(/It reads .* graph and writes/, text("intent end"))
  end

  def test_a_page_with_no_workflow_has_no_workflows_figure_and_a_call_box
    body = text("project list")

    refute_includes body, "workflows.svg"
    assert_includes body, "call.svg"
  end

  def test_the_outcomes_table_names_the_exit_and_the_code
    assert_includes text("intent end"), "| Ending | Exit | next: | Code |"
  end

  def prose(page) = CommandReference::Markdown::Prose.lines(page.comment).first

  def test_a_page_with_no_workflow_names_the_command_call_in_the_events_and_never_the_old_headings
    OWN_CALL_PAGES.reject { |words| words.start_with?("hook") }.each do |words|
      body = text(words)

      refute_includes body, "Before the chain", words
      assert_match(/The command's `call`, at \[`\w+\.rb:\d+`\]/, body, words)
    end
  end

  def test_a_command_page_names_its_call_and_a_hook_page_names_its_respond
    assert_match(/The command's `call`, at \[`status\.rb:\d+`\]/, text("status"))
    assert_match(/The hook's `respond`, at \[`stop.rb:\d+`\]/, text("hook stop"))
    refute_includes text("hook stop"), "own `call`"
  end

  def test_a_routine_with_its_own_call_tells_it_before_the_workflows
    assert_includes text("update"), "### The command's own call"
    assert_includes text("update"), "runs first, then starts the workflow"
  end

  def test_the_class_comment_is_skipped_when_it_repeats_the_summary_and_kept_when_it_adds_more
    status = page("status")
    sync = page("sync up")

    refute_includes text("status"), prose(status)
    refute_includes text("hook stop"), prose(page("hook stop"))
    assert_includes text("sync up"), prose(sync)
  end

  def test_the_ending_column_holds_words_and_never_raw_ruby
    readmes.each do |path, body|
      endings = body[/## How a call ends.*?(?=\n## What the page leaves out)/m].to_s

      refute_empty endings, path
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
