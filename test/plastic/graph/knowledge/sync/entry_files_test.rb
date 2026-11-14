# frozen_string_literal: true

require "json"
require_relative "../../../../test_helper"

class KnowledgeSyncEntryFilesTest < Plastic::TestCase
  Print = Plastic::Graph::Prints::Print

  INDEX = "store/index.json"
  PRETTY = "{\n  \"a\": 1\n}\n"

  def entry_of(path, printed, text) = Plastic::Graph::Knowledge::Sync::EntryFiles.new(folder).entry(path, printed, Print.text(path, :work, text))

  def built(path, bytes, printed: "p", print_text: PRETTY)
    write(path, bytes)
    entry_of(path, printed, print_text)
  end

  def test_a_generated_file_with_the_content_of_its_print_in_other_bytes_is_level
    entry = built(INDEX, JSON.generate({ "a" => 1 }))

    assert_equal [true, false], [entry.level?, entry.hand_edited?]
  end

  def test_a_generated_file_with_other_content_than_its_print_is_hand_edited
    assert_predicate built(INDEX, JSON.generate({ "a" => 2 })), :hand_edited?
  end

  def test_a_generated_file_that_is_not_json_is_hand_edited
    assert_predicate built(INDEX, "{"), :hand_edited?
  end

  def test_a_context_file_is_compared_by_content_as_the_index_is
    assert_predicate built("store/1--alpha/context.json", JSON.generate({ "a" => 1 })), :level?
  end

  def test_a_kept_file_with_the_content_of_its_print_in_other_bytes_is_hand_edited
    assert_predicate built("store/1--alpha/graph.json", JSON.generate({ "a" => 1 })), :hand_edited?
  end

  def test_a_generated_file_missing_from_the_folder_is_not_level
    entry = entry_of(INDEX, "p", PRETTY)

    assert_equal [nil, false], [entry.file_sha, entry.level?]
  end
end
