# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 24, the part row of the clusters: its path, its digest and its record in the printed table.
class KnowledgeSyncTwoHomesClusterPartTest < Plastic::TestCase
  include TwoHomesClusterHelper

  ClusterPart = Plastic::Graph::Prints::ClusterPart

  def test_the_digest_of_the_clusters_is_the_same_for_two_orders_of_the_same_clusters
    one = [{ "name" => "b", "intents" => %w[2 1] }, { "name" => "a", "intents" => ["3"] }]
    other = [{ "name" => "a", "intents" => ["3"] }, { "name" => "b", "intents" => %w[1 2] }]

    assert_equal ClusterPart.digest(one), ClusterPart.digest(other)
  end

  def test_one_intent_changed_on_the_second_home_is_no_change_of_the_clusters
    to_both_homes do |_a, b|
      call_in(b, "intent", "new", "Gamma")
      up = call_in(b, "sync", "up")
      down = call_in(b, "sync", "down")

      assert_equal [0, 0, [%w[one 1]]], [up.code, down.code, clusters(b)], said(up) + said(down)
    end
  end

  def test_a_part_with_no_printed_row_gives_no_conflict_and_the_next_print_writes_the_row
    to_both_homes do |_a, b|
      database_of(b, :work).transaction { |batch| batch.remove(:printed, path: PART) }
      up = call_in(b, "sync", "up")
      call_in(b, "sync", "down")

      assert_equal [0, true], [up.code, printed_part?(b)], said(up)
    end
  end

  def test_the_first_print_records_the_part_row
    to_both_homes do |a, _b|
      assert printed_part?(a)
    end
  end
end
