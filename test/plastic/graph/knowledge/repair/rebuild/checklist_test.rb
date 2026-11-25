# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/knowledge/repair/rebuild/checklist"

# An old checklist gives its steps, with their ticks, and its dated session log rows.
class RebuildChecklistTest < Minitest::Test
  Checklist = Plastic::Graph::Knowledge::Repair::Rebuild::Checklist

  TEXT = <<~MD
    # Checklist: Solo gate

    ## Completed
    - [x] ACTION_1 - doctor.rb: `section_structure` fixable
    - [ ] ACTION_2 - skills table row,
          continued on a second line
        - [x] nested step

    ## Session Log
    | Date | Items Completed | Notes |
    |------|-----------------|-------|
    | 2026-07-02 | ACTION_1, ACTION_2 | Left the cross-store hint alone. |
    | 2026-07-03 |  | Notes with a | pipe. |
  MD

  def test_each_item_gives_its_words_and_its_tick
    items = Checklist.new(TEXT).items

    assert_equal [["ACTION_1 - doctor.rb: `section_structure` fixable", true], ["ACTION_2 - skills table row, continued on a second line", false], ["nested step", true]],
      items.map { |item| [item.title, item.done] }
  end

  def test_a_dated_row_gives_its_date_items_and_notes
    rows = Checklist.new(TEXT).log_rows

    assert_equal [["2026-07-02", "ACTION_1, ACTION_2", "Left the cross-store hint alone."], ["2026-07-03", "", "Notes with a | pipe."]],
      rows.map { |row| [row.date, row.items, row.notes] }
  end

  def test_an_item_inside_the_session_log_is_not_a_step
    text = "- [x] real\n\n## Session Log\n- [x] not a step\n"

    assert_equal ["real"], Checklist.new(text).items.map(&:title)
  end

  def test_a_checklist_with_no_item_gives_none
    assert_empty Checklist.new("# Checklist\n\nNothing yet.\n").items
  end
end
