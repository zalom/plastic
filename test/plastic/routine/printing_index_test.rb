# frozen_string_literal: true

require "json"
require_relative "../../test_helper"

class RoutinePrintingIndexTest < Plastic::TestCase
  include LifecycleHelper
  include HandEditHelper

  def test_an_edited_index_refuses_intent_new_with_no_intent_written
    open_intent
    write("store/index.json", "{}\n")
    result = cli("intent", "new", "Second")

    assert_refused(result, "store/index.json")
    assert_nil retrieval.intent("2")
  end

  def test_a_changed_index_that_was_never_printed_refuses_intent_new_with_no_intent_written
    write("store/index.json", "{}\n")
    result = cli("intent", "new", "First")

    assert_refused(result, "store/index.json")
    assert_nil retrieval.intent("1")
  end

  def compact_index
    write("store/index.json", JSON.generate(JSON.parse(File.read(store_path("store/index.json")))))
  end

  def printed_index = JSON.pretty_generate(JSON.parse(File.read(store_path("store/index.json")))) + "\n"

  def test_a_re_indented_index_lets_approve_pass_and_is_printed_again
    specified
    compact_index
    result = cli("intent", "approve", "1")

    assert_equal [0, true], [result.code, File.read(store_path("store/index.json")) == printed_index]
  end

  def test_a_re_indented_index_lets_intent_new_pass_and_is_printed_again
    open_intent
    compact_index
    result = cli("intent", "new", "Beta")

    assert_equal [0, true, "Beta"], [result.code, File.read(store_path("store/index.json")) == printed_index, retrieval.intent("2")&.title]
  end

  def test_an_index_that_was_never_printed_is_cleared_by_sync_up_and_intent_new_passes
    write("store/index.json", "{}\n")
    refused = cli("intent", "new", "First")
    named = cli("sync", "up")
    again = cli("intent", "new", "First")

    assert_equal [1, "next: plastic sync up", 0, 0], [refused.code, refused.out[/^next: .*$/], named.code, again.code], again.err
  end

  def add_imported_cluster
    data = JSON.parse(File.read(store_path("store/index.json")))
    write("store/index.json", JSON.generate(data.merge("clusters" => [{ "name" => "imported", "intents" => ["1"] }])))
  end

  def test_an_index_with_other_content_than_the_rows_is_refused_though_printed_before_and_sync_up_clears_it
    open_intent
    add_imported_cluster
    results = [cli("intent", "new", "Beta"), cli("sync", "up"), cli("intent", "new", "Beta")]

    assert_equal [1, 0, 0], results.map(&:code), results.last.err
    assert_includes File.read(store_path("store/index.json")), "imported"
  end

  def open_roadmap
    cli("roadmap", "new", "r1")
    cli("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "Batch goal", "--done", "batch done")
    cli("roadmap", "add", "r1", "1", "a", "--title", "A", "--goal", "Item goal", "--done", "item done")
  end

  def test_an_edited_index_refuses_roadmap_open
    open_intent
    open_roadmap
    write("store/index.json", "{}\n")

    assert_refused(cli("roadmap", "open", "r1", "a"), "store/index.json")
  end

  def test_an_edited_roadmap_file_refuses_roadmap_open
    open_roadmap
    write("roadmaps/r1.md", "# by hand\n")

    assert_refused(cli("roadmap", "open", "r1", "a"), "roadmaps/r1.md")
  end
end
