# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"

class SyncUpGeneratedTest < Plastic::TestCase
  include LifecycleHelper

  def index_path = store_path("store/index.json")

  def index_with_cluster
    data = JSON.parse(File.read(index_path))
    write("store/index.json", JSON.generate(data.merge("clusters" => [{ "name" => "imported", "intents" => ["1"] }])))
  end

  def test_sync_up_keeps_a_context_file_that_has_no_rows
    intent = open_intent
    path = "#{intent.dir}/context.json"
    write(path, "{}\n")
    result = cli("sync", "up")

    assert_equal [0, "{}\n"], [result.code, File.read(store_path(path))], result.err
  end

  def test_sync_up_prints_a_generated_index_with_other_content_and_leaves_it_level
    open_intent
    index_with_cluster
    result = cli("sync", "up")
    printed = File.read(index_path)

    assert_equal [0, "#{JSON.pretty_generate(JSON.parse(printed))}\n", true], [result.code, printed, printed.include?("imported")], result.err
  end

  def test_a_preview_of_sync_up_counts_the_generated_file_it_would_print_and_changes_nothing
    open_intent
    index_with_cluster
    before = File.read(index_path)
    result = cli("sync", "up", "--dry-run")

    assert_equal [0, true, before], [result.code, result.out.include?("paths that would change: 1"), File.read(index_path)], result.err
  end

  def test_sync_up_leaves_a_re_indented_index_alone
    open_intent
    compact = JSON.generate(JSON.parse(File.read(index_path)))
    write("store/index.json", compact)
    result = cli("sync", "up")

    assert_equal [0, compact], [result.code, File.read(index_path)], result.err
  end

  def test_sync_up_names_the_overwrite_that_clears_a_file_it_cannot_read
    specified
    other = open_intent("Beta")
    write("#{other.dir}/graph.json", "{\"hand\":true}\n")
    result = cli("sync", "up")

    assert_equal [1, true], [result.code, result.out.include?("sync down --overwrite #{other.dir}/graph.json")], result.err
  end
end
