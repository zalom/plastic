# frozen_string_literal: true

require_relative "../support/kernel"

class WrittenPhraseTest < Minitest::Test
  include KernelFixtures::DatabaseHome

  def test_nothing_written_has_no_phrase
    assert_nil @database.written_phrase
  end

  def test_one_table_written_is_one_phrase
    insert("a")
    insert("b")

    assert_equal "2 routine runs in work_graph.db", @database.written_phrase
  end

  def test_two_tables_join_with_and
    insert("a")
    insert("t", table: :tallies)

    assert_equal "1 routine run and 1 tallies in work_graph.db", @database.written_phrase
  end

  def test_three_tables_join_with_commas
    insert("a")
    insert("t", table: :tallies)
    insert("n", table: :notes)

    assert_equal "1 routine run, 1 tallies, and 1 notes in work_graph.db", @database.written_phrase
  end

  def test_an_uncounted_write_is_kept_off_the_phrase
    @database.transaction { |batch| batch.add("INSERT INTO notes VALUES ('x')") }

    assert_nil @database.written_phrase
  end

  def test_a_write_that_changes_nothing_counts_nothing
    @database.transaction { |batch| batch.write(:notes, "DELETE FROM notes") }

    assert_nil @database.written_phrase
  end
end
