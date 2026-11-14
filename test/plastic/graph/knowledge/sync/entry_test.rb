# frozen_string_literal: true

require "json"
require_relative "../../../../test_helper"

class KnowledgeSyncEntryTest < Plastic::TestCase
  Entry = Plastic::Graph::Knowledge::Sync::Entry
  Print = Plastic::Graph::Prints::Print

  # The action up and down for a file hash, a recorded hash and a rows hash.
  def actions(file, printed, rows)
    entry = Entry.new("p", file, printed, rows ? Print.new("p", :work, rows, nil) : Entry::NO_PRINT)
    %i[up down].map { |direction| entry.action(direction) }
  end

  def test_a_level_file_already_recorded_needs_nothing
    assert_equal %i[none none], actions("a", "a", "a")
  end

  def test_a_level_file_not_yet_recorded_is_recorded
    assert_equal %i[record record], actions("a", nil, "a")
  end

  def test_a_hand_edit_is_read_up_and_left_down
    assert_equal %i[read none], actions("b", "a", "a")
  end

  def test_a_row_change_is_printed_down_and_left_up
    assert_equal %i[none print], actions("a", "a", "b")
  end

  def test_a_missing_file_with_rows_is_printed_down
    assert_equal %i[none print], actions(nil, "a", "a")
  end

  def test_a_change_on_both_sides_is_a_conflict
    assert_equal %i[conflict conflict], actions("b", "a", "c")
  end

  def test_a_new_file_with_no_rows_is_read_up
    assert_equal %i[read none], actions("b", nil, nil)
  end

  GRAPH = "store/1--alpha/graph.json"

  def graph_entry(file, printed, rows) = Entry.new(GRAPH, file, printed, Print.new(GRAPH, :work, rows, nil))

  def graph_actions(*hashes) = %i[up down].map { |direction| graph_entry(*hashes).action(direction) }

  def empty_graph_sha = Plastic::Graph::Prints.empty_graph_sha(GRAPH)

  def test_graph_json_is_not_a_generated_path_but_context_json_and_the_index_are
    generated = ->(path) { Entry.new(path, "a", "a", Entry::NO_PRINT).generated? }

    assert_equal [false, true, true], [GRAPH, "store/1--alpha/context.json", "store/index.json"].map(&generated)
  end

  def test_a_hand_edited_graph_json_is_read_up
    assert_equal %i[read none], graph_actions("b", "a", "a")
  end

  def test_a_graph_changed_on_both_sides_is_a_conflict
    assert_equal %i[conflict conflict], graph_actions("b", "a", "c")
  end

  def test_a_graph_file_against_bare_rows_with_no_record_is_read_and_no_conflict
    assert_equal %i[read none], graph_actions("b", nil, empty_graph_sha)
  end

  def test_bare_rows_count_as_changed_once_a_print_was_recorded
    assert_equal %i[conflict conflict], graph_actions("b", "a", empty_graph_sha)
  end

  INDEX = "store/index.json"
  PRETTY = "{\n  \"a\": 1\n}\n"

  def built(path, bytes, printed: "p", print_text: PRETTY)
    write(path, bytes)
    Entry.for(folder, path, printed, Print.text(path, :work, print_text))
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
    entry = Entry.for(folder, INDEX, "p", Print.text(INDEX, :work, PRETTY))

    assert_equal [nil, false], [entry.file_sha, entry.level?]
  end

  OURS = "{\n  \"origin_id\": \"ours\",\n  \"intents\": []\n}\n"

  def test_an_index_that_another_home_printed_is_printed_from_the_rows_both_ways
    entry = built(INDEX, JSON.generate({ "origin_id" => "theirs", "intents" => [] }), print_text: OURS)

    assert_equal [false, false, %i[print print]], [entry.level?, entry.hand_edited?, %i[up down].map { |way| entry.action(way) }]
  end

  def test_an_index_that_is_a_json_array_is_a_hand_edit_and_raises_nothing
    entry = built(INDEX, "[]", print_text: OURS)

    assert_equal [true, false], [entry.hand_edited?, entry.printed_elsewhere]
  end

  def hand_edited(file, printed, rows) = Entry.new("p", file, printed, rows ? Print.new("p", :work, rows, nil) : Entry::NO_PRINT).hand_edited?

  def test_a_changed_file_that_the_print_does_not_match_is_hand_edited
    assert hand_edited("b", "a", "a")
  end

  def test_a_level_file_is_not_hand_edited
    refute hand_edited("a", "a", "a")
    refute hand_edited("a", nil, "a")
  end

  def test_a_changed_file_with_no_record_of_a_print_is_hand_edited
    assert hand_edited("b", nil, "a")
  end

  def test_a_missing_file_is_not_hand_edited
    refute hand_edited(nil, "a", "a")
  end

  def test_a_graph_file_against_bare_rows_with_no_record_is_not_hand_edited
    refute_predicate graph_entry("b", nil, empty_graph_sha), :hand_edited?
  end

  def test_a_graph_file_changed_since_its_print_is_hand_edited
    assert_predicate graph_entry("b", "a", "a"), :hand_edited?
  end

  def test_an_emptied_graph_file_is_read_up_like_any_hand_edit
    assert_equal %i[read none], graph_actions(empty_graph_sha, "a", "a")
  end
end
