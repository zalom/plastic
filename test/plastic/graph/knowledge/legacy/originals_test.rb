# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyOriginalsTest < Plastic::TestCase
  def originals = Plastic::Graph::Knowledge::Legacy::Originals.new

  def kept = store_graphs.databases[:references].rows("SELECT name, intent_id FROM sqlar ORDER BY name").map(&:values)

  def test_a_rewritten_file_keeps_its_original_bytes_under_its_intent
    counts = Hash.new(0)
    write("store/4--alpha/4--alpha.md", "after")
    originals.keep_changed_originals(store_graphs.databases, folder, { "store/4--alpha/4--alpha.md" => "before" }, counts)

    assert_equal [["originals/store/4--alpha/4--alpha.md", "4"]], kept
    assert_equal 1, counts[:kept]
  end

  def test_an_unchanged_file_keeps_nothing
    write("store/4--alpha/4--alpha.md", "same")
    originals.keep_changed_originals(store_graphs.databases, folder, { "store/4--alpha/4--alpha.md" => "same" }, Hash.new(0))

    assert_empty kept
  end

  def test_a_removed_file_keeps_its_original
    originals.keep_changed_originals(store_graphs.databases, folder, { "store/4--alpha/spec.md" => "before" }, Hash.new(0))

    assert_equal [["originals/store/4--alpha/spec.md", "4"]], kept
  end

  def test_a_rewritten_roadmap_keeps_its_original_with_no_intent
    write("roadmaps/plan.md", "after")
    originals.keep_roadmap_original(store_graphs.databases, folder.path("."), "plan", "before", Hash.new(0))

    assert_equal [["originals/roadmaps/plan.md", nil]], kept
  end

  def test_an_unchanged_roadmap_keeps_nothing
    write("roadmaps/plan.md", "same")
    originals.keep_roadmap_original(store_graphs.databases, folder.path("."), "plan", "same", Hash.new(0))

    assert_empty kept
  end
end
