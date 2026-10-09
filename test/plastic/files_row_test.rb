# frozen_string_literal: true

require_relative "../test_helper"

class FilesRowTest < Plastic::TestCase
  include LifecycleHelper

  def run_cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def files_of(call) = JSON.parse(call.out).dig("result", "files")

  def add_node(*options) = run_cli("node", "add", "1", "first", "--criterion", "done", *options)

  def test_a_writing_call_names_the_files_it_printed_relative_to_the_store_folder
    intent = open_keyed_intent

    result = add_node("--json")

    assert_includes files_of(result), "#{intent.dir}/graph.json"
    assert_empty(files_of(result).select { |path| path.start_with?("/") })
  end

  def test_the_text_answer_lists_the_files_under_one_label
    intent = open_keyed_intent

    result = add_node

    assert_match(%r{^files:  +store/}, result.out)
    assert_includes result.out, "#{intent.dir}/graph.json"
  end

  def test_no_line_starts_with_printed
    open_keyed_intent

    assert_empty(add_node.out.lines.grep(/^printed /))
  end

  def test_a_call_that_printed_nothing_carries_an_empty_list_in_json_and_no_row_in_text
    open_keyed_intent
    add_node

    assert_equal [], files_of(run_cli("graph", "show", "1", "--json"))
    assert_empty(run_cli("graph", "show", "1").out.lines.grep(/^files:/))
  end

  def test_a_refused_write_lists_no_files
    open_keyed_intent

    result = run_cli("node", "add", "9", "first", "--criterion", "done")

    assert_empty(result.out.lines.grep(/^files:/))
  end

  def test_sync_down_lists_its_files_under_files_and_prints_no_printed_line
    intent = open_keyed_intent
    File.delete(store_path("#{intent.dir}/graph.json"))

    result = run_cli("sync", "down")

    assert_empty(result.out.lines.grep(/^printed /))
    assert_match(%r{^files:\s+#{Regexp.escape(intent.dir)}/graph\.json$}, result.out)
  end

  def test_a_json_answer_with_no_graph_write_still_carries_files
    open_keyed_intent

    assert_equal [], files_of(run_cli("sync", "down", "--json"))
  end
end
