# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLinkWriterTest < Plastic::TestCase
  def setup
    super
    @graphs = store_graphs
    @graphs.work.write_intent(title: "Alpha")
    @graphs.work.write_intent(title: "Beta")
  end

  def writer = Plastic::Graph::Knowledge::Link::Writer.new(@graphs.databases, @graphs.retrieval)

  def test_a_link_between_two_intents_of_the_store_has_no_problem
    assert_nil writer.target_problem("1", "2")
  end

  def test_a_link_from_a_missing_intent_is_refused
    assert_equal "no intent 9 in this store", writer.target_problem("9", "2")
  end

  def test_a_link_to_a_missing_local_intent_is_refused
    assert_equal "no intent 9 in this store", writer.target_problem("1", "9")
  end

  def test_a_link_to_a_missing_ruling_is_refused_and_to_a_present_one_is_not
    @graphs.work.add_ruling(intent_id: "2", text: "Ship it")

    assert_equal ["no ruling 2/D9 in this store", nil], [writer.target_problem("1", "2/D9"), writer.target_problem("1", "2/D1")]
  end

  def test_a_target_with_a_store_prefix_is_kept_as_written
    assert_nil writer.target_problem("1", "global:25")
  end

  def test_a_self_link_is_refused
    assert_equal "intent 1 cannot link to itself", writer.refusal("1", "1", "chain")
  end

  def test_a_link_already_there_is_refused
    writer.add_link(from_ref: "1", to_ref: "2", kind: "chain")

    assert_equal ["intent 1 already has a chain link to 2", nil], [writer.refusal("1", "2", "chain"), writer.refusal("1", "2", "cites")]
  end

  def test_a_second_identical_link_fails_the_write
    writer.add_link(from_ref: "1", to_ref: "2", kind: "chain")

    assert_raises(Plastic::Graph::Database::Error) { writer.add_link(from_ref: "1", to_ref: "2", kind: "chain") }
  end

  def test_remove_link_reports_whether_it_removed_a_row
    writer.add_link(from_ref: "1", to_ref: "2", kind: "chain")

    assert_equal [true, false], Array.new(2) { writer.remove_link(from_ref: "1", to_ref: "2", kind: "chain") }
    assert_empty @graphs.retrieval.links("1")
  end
end
