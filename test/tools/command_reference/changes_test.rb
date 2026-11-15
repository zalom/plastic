# frozen_string_literal: true

require_relative "../../command_reference_helper"

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

  def test_a_row_of_the_backups_folder_goes_with_the_store
    assert_equal "goes with the store", reach_of(:backups, [])
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

  def test_a_print_of_the_roadmap_adds_the_row_of_its_files
    assert_equal ["The files of the roadmap are rewritten"], rows({}, [:roadmap]).map(&:text)
  end

  def test_a_command_with_no_change_and_no_print_has_no_row
    assert_empty rows({})
  end

  def test_the_same_change_declared_twice_is_one_row
    assert_equal 1, rows({ work: "A thing changes" }, []).size
  end

  def test_the_rows_of_intent_end_hold_the_change_the_lock_and_the_files
    texts = page("intent end").changes.map(&:text)

    assert_includes texts, "The intent is marked done and its completion is saved"
    assert_includes texts, "The lock of the intent is released"
    assert_includes texts, "The files of the intent and the index of the store are rewritten"
  end

  def test_roadmap_show_has_no_row
    assert_empty page("roadmap show").changes
  end
end
