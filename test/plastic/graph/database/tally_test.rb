# frozen_string_literal: true

require_relative "../../../test_helper"

class DatabaseTallyTest < Plastic::TestCase
  Tally = Plastic::Graph::Database::Tally

  def tally = Tally.new("work_graph.db")

  def test_a_new_tally_wrote_nothing
    assert_equal [{}, false, nil, []], [tally.to_h, tally.wrote_rows?, tally.phrase, tally.phrases]
  end

  def test_rows_add_up_by_table_and_the_command_run_counts_once
    counted = tally
    counted.count("intents", 1)
    counted.count("intents", 2)
    counted.count(Plastic::Graph::Database::RUNS, 1)
    counted.count(Plastic::Graph::Database::RUNS, 1)

    assert_equal({ "intents" => 3, Plastic::Graph::Database::RUNS => 1 }, counted.to_h)
  end

  def test_the_phrase_names_the_rows_and_the_file_and_leaves_the_command_run_out
    counted = tally
    counted.count("intents", 1)
    counted.count(Plastic::Graph::Database::RUNS, 1)

    assert_equal "1 intent in work_graph.db", counted.phrase
  end

  def test_only_a_command_run_is_not_a_write
    counted = tally
    counted.count(Plastic::Graph::Database::RUNS, 1)

    assert_equal [false, nil], [counted.wrote_rows?, counted.phrase]
  end

  def test_a_failing_block_gives_the_counts_back
    counted = tally
    counted.count("intents", 1)

    assert_raises(RuntimeError) { counted.keeping { counted.count("intents", 4) && raise("refused") } }
    assert_equal({ "intents" => 1 }, counted.to_h)
  end
end
