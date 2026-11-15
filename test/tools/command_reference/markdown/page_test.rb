# frozen_string_literal: true

require_relative "../../../command_reference_helper"
require_relative "../../../docs_stale_words_guard_test"

class CommandReferenceMarkdownPageTest < Minitest::Test
  include CommandReferenceHelper

  OLD_HEADINGS = ["What it touches", "How the call flows", "## Outcomes", "\n## The command", "Before the chain", "## Components", "## How a call ends", "## What the page leaves out"].freeze

  def text(words) = CommandReference::Markdown::Page.new(page(words)).to_s

  def readmes = CommandReferenceHelper.files.select { |path, _| path.match?(%r{/commands/[^/]+/README\.md\z}) }

  def prose(page) = CommandReference::Markdown::Prose.lines(page.comment).first

  def test_no_built_page_holds_a_stale_phrase
    CommandReferenceHelper.files.each do |path, body|
      assert_empty body.scan(DocsStaleWordsGuardTest::STALE), path
    end
  end

  def test_no_command_page_keeps_an_old_heading
    readmes.each { |path, body| assert_empty OLD_HEADINGS.select { |old| body.include?(old) }, path }
  end

  def test_a_page_with_several_workflows_shows_the_workflows_drawing_before_the_events_drawing
    body = text("intent end")

    assert_operator body.index("workflows.svg"), :<, body.index("events.svg")
  end

  def test_a_page_with_one_workflow_or_none_shows_no_workflows_drawing
    refute_includes text("project links"), "workflows.svg"
  end

  def test_the_class_comment_is_skipped_when_it_repeats_the_summary_and_kept_when_it_adds_more
    status = page("status")
    sync = page("sync up")

    refute_includes text("status"), prose(status)
    refute_includes text("hook stop"), prose(page("hook stop"))
    assert_includes text("sync up"), prose(sync)
  end
end
