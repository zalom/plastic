# frozen_string_literal: true

require_relative "../../../command_reference_helper"
require_relative "../../../docs_stale_words_guard_test"

class CommandReferenceMarkdownPageTest < Minitest::Test
  include CommandReferenceHelper

  OLD_HEADINGS = ["What it touches", "How the call flows", "## Outcomes", "\n## The command", "Before the chain", "## Components", "## How a call ends", "## What the page leaves out"].freeze

  def text(words) = CommandReference::Markdown::Page.new(page(words)).to_s

  def readmes = CommandReferenceHelper.files.select { |path, _| path.match?(%r{/commands/[^/]+/README\.md\z}) }

  def test_no_built_page_holds_a_stale_phrase
    CommandReferenceHelper.files.each do |path, body|
      assert_empty body.scan(DocsStaleWordsGuardTest::STALE), path
    end
  end

  def test_no_command_page_keeps_an_old_heading
    readmes.each { |path, body| assert_empty OLD_HEADINGS.select { |old| body.include?(old) }, path }
  end

  def test_the_page_of_a_command_with_a_long_description_prints_its_lines_after_the_summary
    body = text("console")

    assert_operator body.index("The console is no sandbox: Ruby can still write files."), :>, body.index("```sh")
  end

  def test_a_page_with_several_workflows_shows_the_workflows_drawing_before_the_events_drawing
    body = text("intent end")

    assert_operator body.index("workflows.svg"), :<, body.index("events.svg")
  end

  def test_a_page_with_one_workflow_or_none_shows_no_workflows_drawing
    refute_includes text("project links"), "workflows.svg"
  end

  def test_every_page_holds_one_description_and_then_its_call
    readmes.each do |path, body|
      lines = body.lines(chomp: true)

      assert_equal ["", "```sh"], [lines[3], lines[4]], path
    end
  end
end
