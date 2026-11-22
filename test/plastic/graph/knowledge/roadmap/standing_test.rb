# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeRoadmapStandingTest < Plastic::TestCase
  Roadmap = Plastic::Graph::Knowledge::Roadmap

  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    @fields = Roadmap::Fields.new(title: nil, goal: nil, done: nil)
    @graphs.work.write_batch("plan", 1, fields: @fields)
    @graphs.work.add_item("plan", "a", 1, fields: @fields, needs: [])
  end

  def standing(slug = "plan") = Roadmap::Standing.new(@graphs.databases, @graphs.retrieval, slug)

  def test_a_roadmap_exists_once_it_is_written
    assert_equal [true, false], [standing.exists?, standing("other").exists?]
  end

  def test_a_batch_is_found_by_its_position
    assert_equal ["Batch 1", nil], [standing.batch(1).title, standing.batch(2)]
  end

  def test_the_words_of_a_new_batch_are_called_batch_n
    assert_equal "Batch 2", standing.kept_words(2, @fields).title
  end

  def test_an_item_held_has_no_new_position_and_a_new_one_takes_the_next
    assert_equal [nil, 2], [standing.new_item_position("a", 1), standing.new_item_position("b", 1)]
  end

  def test_the_next_log_position_follows_the_last_line
    @graphs.work.add_log("plan", "first")

    assert_equal [2, "first"], [standing.next_log_position, standing.last_log.text]
  end

  def test_a_missing_batch_is_a_failure
    assert_equal ["no batch 2 on roadmap plan", :failure], standing.addition_problem("b", 2, [])
  end

  def test_a_missing_item_is_a_failure
    assert_equal ["no item z on roadmap plan", :failure], standing.addition_problem("b", 1, ["z"])
  end

  def test_an_item_after_itself_is_a_loop_refusal
    assert_equal ["an edge from a to a would loop: a -> a", :refusal], standing.addition_problem("a", 1, ["a"])
  end

  def test_an_item_that_breaks_nothing_has_no_problem
    assert_nil standing.addition_problem("b", 1, ["a"])
  end
end
