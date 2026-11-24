# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/revisions"

class RepairRevisionsTest < Plastic::TestCase
  Revisions = Plastic::Graph::Knowledge::Repair::Revisions

  HEADINGS = <<~TEXT
    # revisions.md

    ## Revision v1 - 2026-08-31-20:09
    - Why: regenerated the links
    - Change: ## Links regenerated

    ## Revision v2 - 2026-09-22

    Why: reconcile the record.

    ```markdown
    ## In Progress
    ```
  TEXT

  def entries(text, zone: "+02:00") = Revisions.new(text, zone:).entries

  def test_each_revision_heading_is_one_entry_with_its_label
    assert_equal %w[v1 v2], entries(HEADINGS).map(&:label)
  end

  def test_a_heading_time_without_an_offset_reads_in_the_given_zone
    assert_equal %w[2026-08-31T18:09:00Z 2026-09-21T22:00:00Z], entries(HEADINGS).map(&:at)
  end

  def test_the_text_of_an_entry_is_one_line_and_keeps_its_headings_inside_a_fence
    assert_equal "Why: reconcile the record. ```markdown ## In Progress ```", entries(HEADINGS).last.text
  end

  def test_each_dated_bullet_is_one_entry_when_no_heading_is_found
    found = entries("- 2026-07-09T00:00Z  chain += 24 (metadata only)\n")

    assert_equal [["entry 1", "2026-07-09T00:00:00Z", "chain += 24 (metadata only)"]], found.map { |entry| [entry.label, entry.at, entry.text] }
  end

  def test_dated_bullets_before_the_first_heading_are_entries_of_their_own
    found = entries("# Revisions\n\n- 2026-08-29 structural: chain += 33\n\n## Revision v1 - 2026-09-01\nWhy: more.\n")

    assert_equal [["entry 1", "2026-08-28T22:00:00Z", "structural: chain += 33"], ["v1", "2026-08-31T22:00:00Z", "Why: more."]],
      found.map { |entry| [entry.label, entry.at, entry.text] }
  end

  def test_a_file_with_an_entry_and_only_a_title_besides_is_readable
    assert_predicate Revisions.new(HEADINGS, zone: "+02:00"), :readable?
  end

  def test_a_file_with_no_entry_is_not_readable
    refute_predicate Revisions.new("# Revisions\n\n", zone: "+02:00"), :readable?
  end

  def test_a_file_with_other_text_before_the_first_heading_is_not_readable
    refute_predicate Revisions.new("# Revisions\n\nNothing dated here.\n\n## Revision v1 - 2026-09-01\nWhy.\n", zone: "+02:00"), :readable?
  end

  def test_without_a_zone_a_time_reads_in_the_zone_of_the_machine
    found = Revisions.new("## Revision v1 - 2026-08-31-20:09\nWhy.\n").entries.first

    assert_equal Plastic.timestamp(Time.new(2026, 8, 31, 20, 9)), found.at
  end
end
