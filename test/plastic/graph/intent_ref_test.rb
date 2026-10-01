# frozen_string_literal: true

require_relative "../../test_helper"

class IntentRefTest < Plastic::TestCase
  IntentRef = Plastic::Graph::IntentRef

  # The retrieval graph as a ref reads it: the origin id and one intent.
  Retrieval = Data.define(:origin_id, :ids) do
    def intent(intent_id) = ids.include?(intent_id) || nil
  end

  def retrieval = Retrieval.new("a1b2", ["5"])

  def test_a_ref_written_as_id_and_origin_names_an_intent
    assert_equal [%w[5a a1b2], %w[12 beef]], %w[5a-a1b2 12-beef].map { |ref| IntentRef.parse(ref).to_h.values }
  end

  def test_other_refs_name_no_intent
    assert_equal [nil] * 5, ["ENG-12", "5-abc", "x5-a1b2", "5-a1b2 ", nil].map { |ref| IntentRef.parse(ref) }
  end

  def test_a_ref_to_an_intent_this_store_holds_stands
    assert_nil IntentRef.parse("5-a1b2").problem(retrieval)
  end

  def test_a_ref_to_another_installation_stands
    assert_nil IntentRef.parse("9-beef").problem(retrieval)
  end

  def test_a_ref_to_a_missing_intent_of_this_installation_is_a_problem
    assert_equal "no intent 9 of this installation for the ref", IntentRef.parse("9-a1b2").problem(retrieval)
  end

  def test_the_line_says_whose_intent_the_ref_names
    assert_equal ["ref: intent 5 of this installation", "ref: intent 9 of installation beef, not in this store"],
      %w[5-a1b2 9-beef].map { |ref| IntentRef.parse(ref).line("a1b2") }
  end
end
