# frozen_string_literal: true

require_relative "../../command_reference_helper"
require "plastic/code_workflow"

class CommandReferenceChangesTest < Minitest::Test
  include CommandReferenceHelper

  Klass = Struct.new(:changes, :prints)

  def rows(changes, prints = [], flows = []) = CommandReference::Changes.new(Klass.new(changes, prints), flows).rows

  def reach_of(place, prints) = rows({ place => "A thing changes" }, prints).first.reach

  def test_a_row_of_a_graph_goes_with_the_store_when_the_command_prints
    assert_equal "goes with the store", reach_of(:work, [:intent])
  end

  def test_a_row_of_a_graph_stays_on_this_machine_when_the_command_prints_nothing
    assert_equal "stays on this machine", reach_of(:work, [])
  end

  def test_a_row_of_the_store_folder_goes_with_the_store_even_with_no_print
    assert_equal "goes with the store", reach_of(:store, [])
  end

  def test_a_row_of_the_backups_folder_stays_on_this_machine_because_the_store_does_not_version_database_files
    assert_equal "stays on this machine", reach_of(:backups, [])
    assert_equal "stays on this machine", reach_of(:backups, [:intent])
  end

  def test_a_row_of_the_database_files_of_the_store_stays_on_this_machine
    assert_equal "stays on this machine", reach_of(:databases, [:intent])
  end

  def test_a_row_of_the_search_index_the_local_database_the_home_and_the_harness_stays_on_this_machine
    %i[retrieval local home harness].each { |place| assert_equal "stays on this machine", reach_of(place, [:intent]), place.to_s }
  end

  def test_each_place_says_where_it_is_in_words
    assert_equal "the work graph database, in the store folder", rows({ work: "A thing changes" }).first.where
    assert_equal "the local database, in the home folder", rows({ local: "A thing changes" }).first.where
  end

  def test_a_print_of_the_intent_adds_the_row_of_its_files_and_the_index
    assert_includes rows({}, [:intent]).map(&:text), "The files of the intent and the index of the store are rewritten"
  end

  def test_a_print_of_the_index_alone_adds_the_row_of_the_index
    assert_equal ["The index of the store is rewritten"], rows({}, [:index]).map(&:text)
  end

  def test_a_command_with_no_change_and_no_print_has_no_row
    assert_empty rows({})
  end

  def test_the_same_change_declared_by_the_command_and_by_a_step_is_one_row
    step = Plastic::CodeWorkflow::Step.new("write", nil, { work: "A thing changes" }, nil)
    flow = CommandReference::Flow.new(:write, Struct.new(:steps).new([step]), "code", nil, nil, nil, [], [])

    assert_equal ["A thing changes"], rows({ work: "A thing changes" }, [], [flow]).map(&:text)
  end

  def test_a_place_with_two_changes_in_words_gives_a_row_for_each
    assert_equal ["A thing changes", "Another thing changes"], rows({ work: ["A thing changes", "Another thing changes"] }).map(&:text)
  end

  def test_the_claim_of_a_node_names_its_move_to_needing_information
    assert_includes page("node claim").changes.map(&:text), "A node with three runs moves to needing information, with the question for the owner"
  end

  def test_the_rows_of_intent_end_hold_the_change_and_the_files
    texts = page("intent end").changes.map(&:text)

    assert_includes texts, "The intent is marked done, its completion is saved and its driver claim is released"
    refute(texts.any? { |text| text.match?(/lock/i) })
    assert_includes texts, "The files of the intent and the index of the store are rewritten"
  end

  def test_the_rows_of_sync_up_hold_the_files_and_the_index_it_prints_again
    row = page("sync up").changes.find { |each| each.text == "The files of the intents and the index of the store are printed again from the rows" }

    assert_equal "goes with the store", row.reach
  end
end
