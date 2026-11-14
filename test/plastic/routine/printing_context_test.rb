# frozen_string_literal: true

require "json"
require_relative "../../test_helper"

# The hand edit check compares a context file by its content, as it does the index.
class RoutinePrintingContextTest < Plastic::TestCase
  include LifecycleHelper
  include HandEditHelper

  def context_path
    intent = specified
    cli("intent", "discover", "1", "spec")
    path = "#{intent.dir}/context.json"
    flunk "discover printed no context.json" unless folder.exist?(path)
    path
  end

  def context_data(path) = JSON.parse(File.read(store_path(path)))

  def level_context?(path) = File.read(store_path(path)) == "#{JSON.pretty_generate(context_data(path))}\n"

  def test_a_re_indented_context_lets_approve_node_add_and_note_pass_and_is_printed_again
    path = context_path
    write(path, JSON.generate(context_data(path)))
    results = [cli("intent", "approve", "1"), cli("node", "add", "1", "Deliver", "--criterion", KEY), cli("intent", "note", "1", "a line")]
    found = results.map { |result| [result.code, level_context?(path)] }

    assert_equal [[0, true]] * 3, found, results.map(&:err).join
  end

  def edited_context
    path = context_path
    write(path, JSON.generate(context_data(path).merge("context" => { "hand" => true })))
    path
  end

  def test_a_context_with_other_content_than_its_rows_is_refused
    edited_context
    refused = cli("intent", "note", "1", "a line")

    assert_equal [1, "next: plastic sync up"], [refused.code, refused.out[/^next: .*$/]], refused.err
  end

  def test_sync_up_prints_a_context_with_other_content_again_from_its_rows
    path = edited_context
    named = cli("sync", "up")
    again = cli("intent", "note", "1", "a line")

    assert_equal [0, 0, true, false], [named.code, again.code, level_context?(path), File.read(store_path(path)).include?("hand")], again.err
  end
end
