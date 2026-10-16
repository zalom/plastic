# frozen_string_literal: true

require_relative "../../../command_reference_helper"

class CommandReferenceMarkdownTouchingTest < Minitest::Test
  include CommandReferenceHelper

  def text(words) = CommandReference::Markdown::Page.new(page(words)).to_s

  def touching(words) = text(words)[/## What one call reads, writes and prints.*?(?=\n## How a call ends)/m]

  def test_the_touching_section_names_every_database_and_printed_file
    body = touching("intent new")

    ["touches.svg", "work_graph.db", "knowledge_graph.db", "references.db", "store/index.json"].each { |part| assert_includes body, part }
    assert_includes body, "| Place | Database or file | Tables | Reads or writes | Code |"
    body[/\| Place.*?\n\n/m].lines.grep(/^\| /).drop(2).each { |row| assert_match(/\.rb#L\d+\) \|\s*\z/, row) }
  end

  def test_a_second_call_table_lists_each_step_and_is_absent_without_one
    body = touching("intent new")

    ["| Step | Done when | The second call | Code |", "| write the intent |"].each { |part| assert_includes body, part }
    ["status", "graph show"].each { |words| refute_includes touching(words), "The second call" }
  end

  def test_the_second_call_table_says_an_always_run_step_runs_again
    assert_includes touching("intent end"), "runs it again"
  end

  def test_a_command_that_touches_no_store_says_so
    body = touching("version")

    assert_includes body, "It reads and writes no store database and prints no store file."
    refute_includes body, "| Place |"
  end

  def test_each_touches_row_links_its_declaration_or_says_found_in_the_code
    assert_match(/\| local\.db \|.*found in the code, not declared/, touching("intent end"))
    assert_match(%r{\| store/index\.json \|.*prints\.rb#L\d+}, touching("intent new"))
    assert_match(/\| work_graph\.db \|.*new\.rb#L\d+/, touching("intent new"))
  end

  def test_a_declared_database_with_no_table_found_is_still_a_row
    assert_includes touching("intent new"), "references.db"
  end

  def test_a_declaration_in_a_shared_options_module_is_linked
    assert_includes touching("sync up"), "sync_options.rb#L"
  end
end
