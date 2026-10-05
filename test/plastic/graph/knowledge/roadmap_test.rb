# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeRoadmapTest < Plastic::TestCase
  Roadmap = Plastic::Graph::Knowledge::Roadmap

  def batch = Roadmap::Batch.from_h({ position: 1, title: "Kept", goal: "Ship batch", done: "Batch done\nAll green" })

  def item(**fields) = Roadmap::Item.from_h({ item: "a", batch: 1, goal: "Ship item", done: "Item done", **fields })

  def test_fields_left_out_keep_the_words_of_the_row
    kept = Roadmap::Fields.new(title: nil, goal: "New goal", done: nil).over(batch, "Batch 1")

    assert_equal ["Kept", "New goal", ["Batch done", "All green"]], [kept.title, kept.goal, kept.done]
  end

  def test_fields_over_no_row_take_the_fallback_title
    kept = Roadmap::Fields.new(title: nil, goal: nil, done: nil).over(nil, "Batch 2")

    assert_equal ["Batch 2", nil, []], [kept.title, kept.goal, kept.done]
  end

  def test_given_done_lines_replace_the_rows_lines
    assert_equal ["Only this"], Roadmap::Fields.new(title: nil, goal: nil, done: "Only this").over(batch, "x").done
  end

  def test_an_item_is_dropped_only_when_marked_dropped
    assert_equal [true, false], [item(mark: "dropped").dropped?, item(mark: "delivered").dropped?]
  end

  def test_an_item_with_an_intent_cannot_start_again
    assert_equal "item a already has an intent", item(intent_id: "4").start_refusal("ready")
  end

  def test_an_item_starts_only_when_ready
    assert_equal ["item a is blocked, not ready", nil], [item.start_refusal("blocked"), item.start_refusal("ready")]
  end

  def test_the_spec_body_joins_the_batch_and_item_goals_and_criteria
    assert_equal "## Goal\n\nShip batch\nShip item\n\n## Done criteria\n\n- [ ] Batch done\n- [ ] All green\n- [ ] Item done\n",
      item.spec_body([batch])
  end
end
