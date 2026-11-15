# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 27: what a read keeps as written, the links of another origin and a home that holds links with no part row.
class KnowledgeSyncTwoHomesLinksKeptTest < Plastic::TestCase
  include TwoHomesLinksHelper

  ENDS = [%w[2 1/D1 cites], %w[2 9 cites], %w[2 global:25 cites]].freeze

  def test_a_link_to_a_ruling_to_a_ref_of_another_store_and_to_an_archived_intent_is_kept_as_written
    to_both_homes do |a, b|
      ENDS.each { |from, to, kind| put_link(a, from, kind, to) }
      call_in(a, "sync", "down")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, ENDS.sort], [up.code, links(b)], said(up)
    end
  end

  def test_a_read_leaves_the_links_of_another_origin_and_a_second_read_duplicates_no_row
    to_both_homes do |a, b|
      put_link(b, "2", "source", "1", origin: "zzzz")
      link(a, "2", "cites", "1")
      pull(b, a)
      call_in(b, "sync", "up")
      call_in(b, "sync", "up")

      assert_equal [[CITES], [%w[2 1 source]]], [links(b), links(b, origin: "zzzz")]
    end
  end

  def test_a_home_that_holds_links_and_no_part_row_keeps_its_own_adds_the_links_of_the_file_and_prints_both
    to_both_homes do |a, b|
      put_link(b, "1", "chain", "2")
      forget_part(b)
      link(a, "2", "cites", "1")
      pull(b, a)
      up = call_in(b, "sync", "up")

      assert_equal [0, [%w[1 2 chain], CITES], [%w[1 2 chain], CITES], true], [up.code, links(b), listed_keys(b), printed_part?(b)], said(up)
    end
  end
end
