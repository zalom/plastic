# frozen_string_literal: true

require_relative "../support/kernel"

class IntentTest < Minitest::Test
  Intent = Plastic::Graph::Intent

  def test_next_child_alternates_number_and_letter
    calls = [["307", []], ["307", %w[307a]], ["307a", []], ["307a", %w[307a1]]]

    assert_equal %w[307a 307b 307a1 307a2], calls.map { |parent, taken| Intent.next_child(parent, taken) }
  end

  def test_next_root_follows_the_highest_number
    assert_equal "11", Intent.next_root(%w[1 2 10 2a])
    assert_equal "1", Intent.next_root([])
  end

  def test_the_parent_is_the_id_less_its_last_run
    assert_equal ["307a", "307", nil], %w[307a1 307a 307].map { |id| Intent.parent_of(id) }
  end

  def test_ids_sort_in_luhmann_order
    assert_equal %w[1 1a 1a1 1b 2 10], %w[10 1b 2 1a1 1 1a].sort_by { |id| Intent.segments(id) }
  end

  def test_a_slug_comes_from_the_title
    assert_equal "build-the-storage-layer-now", Intent.slug_for("Build the storage layer, now!")
  end
end
