# frozen_string_literal: true

require_relative "../../../command_reference_helper"

class CommandReferenceMarkdownLeavesOutTest < Minitest::Test
  include CommandReferenceHelper

  SHARED = "../../dsl/README.md#what-every-call-shares"
  OWN_CALL_PAGES = ["hook end", "hook stop", "hook start", "graph resume", "project links", "project list", "status", "project new", "config", "config list", "config get", "config set"].freeze

  def text(words) = CommandReference::Markdown::Page.new(page(words)).to_s

  def readmes = CommandReferenceHelper.files.select { |path, _| path.match?(%r{/commands/[^/]+/README\.md\z}) }

  def prose_lines(body) = body.gsub(/^```.*?^```\n/m, "")

  def test_the_page_links_what_every_call_shares_once
    readmes.each { |path, body| assert_equal 1, body.scan(SHARED).size, path }
  end

  def test_exit_3_is_said_never_only_when_no_ending_refuses
    never = "No gate of this command refuses, so exit 3 never happens."

    assert_includes text("intent new"), never
    refute_includes text("auto"), never
    refute_includes text("node remove"), never
  end

  def test_a_command_that_writes_says_a_stop_also_saves_the_routine_run
    assert_match(/routine run/, text("intent new")[/## What the page leaves out.*/m])
    refute_match(/routine run/, text("graph show")[/## What the page leaves out.*/m])
  end

  def test_no_list_item_holds_an_escaped_pipe_a_template_or_a_line_break
    readmes.each do |path, body|
      items = prose_lines(body).lines.grep(/^\d+\. /)

      items.each do |item|
        refute_includes item, "\\|", path
        refute_includes item, "%{", path
      end
    end

    assert_equal 1, text("install").lines.grep(/^\d+\. Gate: .*\|\|/).size
  end

  def test_a_page_shows_placeholders_as_uppercase_words
    body = text("intent new")

    assert_includes body, "PROBLEM"
    refute_includes body, "%{"
  end

  def test_the_steps_of_an_own_call_keep_every_statement
    OWN_CALL_PAGES.each do |words|
      items = text(words).lines.grep(/^\d+\. /).map { |item| item.gsub(/\s+/, " ") }

      statements(words).each { |line| assert(items.any? { |item| item.include?(line) }, "#{words}: #{line}") }
    end
  end

  def statements(words) = page(words).own_call.code[1...-1].map(&:strip).reject(&:empty?)
end
