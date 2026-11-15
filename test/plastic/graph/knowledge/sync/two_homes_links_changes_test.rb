# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 27: links changed on both homes, a part that cannot be read and an index with no links part.
class KnowledgeSyncTwoHomesLinksChangesTest < Plastic::TestCase
  include TwoHomesLinksHelper

  def test_the_same_link_made_on_both_homes_at_two_times_is_recorded_and_is_no_conflict
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      put_link(b, "2", "cites", "1")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, [CITES], true], [up.code, links(b), printed_part?(b)], said(up)
    end
  end

  def test_links_changed_on_both_homes_to_other_keys_are_a_conflict_and_neither_the_rows_nor_the_file_change
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      put_link(b, "2", "source", "1")
      pull(b, a)
      before = files_snapshot(b)
      up = call_in(b, "sync", "up")

      assert_equal [1, [%w[2 1 source]], before], [up.code, links(b), files_snapshot(b)], said(up)
    end
  end

  def test_a_links_part_with_a_kind_outside_the_kinds_is_left_listed_with_its_reason_and_the_rows_stay
    to_both_homes do |a, b|
      link(a, "2", "cites", "1")
      pull(b, a)
      write_links_part(b, [{ "from_ref" => "2", "to_ref" => "1", "kind" => "no-such-kind", "at" => "x" }])
      up = call_in(b, "sync", "up")

      assert_equal [1, [], true, false], [up.code, links(b), said(up).include?("no-such-kind"), said(up).match?(/Invalid|NoMethodError/)], said(up)
    end
  end

  def test_an_index_with_no_links_part_leaves_every_link_in_the_rows_and_sync_down_then_prints_the_part
    to_both_homes do |a, _b|
      link(a, "2", "cites", "1")
      write_links_part(a, nil)
      up = call_in(a, "sync", "up")
      down = call_in(a, "sync", "down")

      assert_equal [0, [CITES], 0, [CITES]], [up.code, links(a), down.code, listed_keys(a)], said(up) + said(down)
    end
  end
end
