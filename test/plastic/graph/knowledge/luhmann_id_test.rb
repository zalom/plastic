# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/knowledge/luhmann_id"

class LuhmannIdTest < Minitest::Test
  ID = Plastic::Graph::Knowledge::LuhmannId

  def test_ids_sort_by_their_runs
    assert_equal %w[307 307a 307a1 307a2 307b 308], %w[308 307b 307a2 307 307a1 307a].sort_by { |id| ID.segments(id) }
  end

  def test_a_number_takes_letter_children
    assert_equal %w[307a 307b], ID.children("307").first(2)
  end

  def test_a_letter_takes_number_children
    assert_equal %w[307a1 307a2], ID.children("307a").first(2)
  end

  def test_the_next_child_skips_the_taken_ids
    assert_equal "307c", ID.next_child("307", %w[307a 307b])
  end

  def test_a_parent_with_every_child_taken_is_invalid
    error = assert_raises(Plastic::Invalid) { ID.next_child("307", ID.children("307")) }

    assert_equal "307 has no free child id", error.message
  end

  def test_the_next_root_follows_the_highest_number
    assert_equal "13", ID.next_root(%w[3 12 12a 7])
  end

  def test_the_first_root_is_1
    assert_equal "1", ID.next_root([])
  end

  def test_the_parent_drops_the_last_run
    assert_equal "307a", ID.parent_of("307a1")
  end

  def test_a_root_has_no_parent
    assert_nil ID.parent_of("307")
  end
end
