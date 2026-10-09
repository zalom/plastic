# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeIntentTest < Plastic::TestCase
  Intent = Plastic::Graph::Knowledge::Intent
  LuhmannId = Plastic::Graph::Knowledge::LuhmannId
  AT = "2026-10-01T10:00:00+02:00"

  def intent(**fields)
    Intent.from_h({ id: 4, intent_id: "1a", parent_id: "1", ref: "ENG-1", origin_id: "o", slug: "build", title: "Build",
                    kind: "work", status: "open", opened_at: AT, updated_at: AT, extra: "dropped" }.merge(fields))
  end

  def test_next_child_alternates_number_and_letter
    calls = [["307", []], ["307", %w[307a]], ["307a", []], ["307a", %w[307a1]]]

    assert_equal %w[307a 307b 307a1 307a2], calls.map { |parent, taken| LuhmannId.next_child(parent, taken) }
  end

  def test_a_parent_with_every_child_taken_has_no_free_id
    error = assert_raises(Plastic::Invalid) { LuhmannId.next_child("7", ("a".."z").map { |letter| "7#{letter}" }) }

    assert_equal "7 has no free child id", error.message
  end

  def test_children_run_to_z_after_a_number_and_to_99_after_a_letter
    assert_equal [26, "7z", 99, "7a99"], [LuhmannId.children("7").size, LuhmannId.children("7").last,
      LuhmannId.children("7a").size, LuhmannId.children("7a").last]
  end

  def test_next_root_follows_the_highest_number
    assert_equal %w[11 1], [LuhmannId.next_root(%w[1 2 10 2a]), LuhmannId.next_root([])]
  end

  def test_the_parent_is_the_id_less_its_last_run
    assert_equal ["307a", "307", nil], %w[307a1 307a 307].map { |id| LuhmannId.parent_of(id) }
  end

  def test_ids_sort_in_luhmann_order
    assert_equal %w[1 1a 1a1 1b 2 10], %w[10 1b 2 1a1 1 1a].sort_by { |id| LuhmannId.segments(id) }
  end

  def test_a_slug_takes_six_words_of_the_title
    assert_equal "build-the-storage-layer-now-for", Intent.slug_for("Build the storage layer, now! For real")
  end

  def test_a_record_drops_unknown_keys_and_reads_missing_ones_as_nil
    found = intent

    assert_equal [4, nil, [[0, 1], [1, "a"]]], [found.id, found.closed_at, found.segments]
  end

  def test_the_folder_and_its_own_file_follow_the_id_and_slug
    assert_equal ["store/1a--build", "intent.md"], [intent.dir, intent.file]
  end

  def test_a_new_row_leaves_the_id_and_origin_to_the_database
    assert_equal %i[intent_id parent_id ref slug title kind status disposition opened_at closed_at updated_at], intent.new_row.keys
  end

  def test_the_first_savepoint_line_names_the_title
    assert_equal({ intent_id: "1a", position: 1, at: AT, text: "Opened: Build", session_id: nil }, intent.first_savepoint)
  end

  def test_the_first_savepoint_line_carries_the_session_that_opened_it
    assert_equal "s-1", intent.first_savepoint("s-1").fetch(:session_id)
  end

  def test_the_own_file_holds_the_front_matter_and_the_sections
    page = ["---", 'id: "1a"', 'intent: "Build"', 'parent: "1"', 'ref: "ENG-1"', 'origin: "o"', %(created: "#{AT}"), "---", "",
      "# 1a - Build", "", "## Intent", "", "Build", "", "## Context", "", "## Outcome", "", "## Insights", ""].join("\n")

    assert_equal({ intent_id: "1a", path: "intent.md", body: page, updated_at: AT }, intent.document("o"))
  end

  def test_the_front_matter_leaves_out_empty_fields
    refute_match(/parent|ref/, intent(parent_id: nil, ref: nil).page("o"))
  end

  def test_the_index_entry_lists_the_index_fields_in_order
    assert_equal %w[intent_id origin_id parent_id ref slug title kind status disposition opened_at closed_at], intent.index_h.keys
    assert_equal "1a", intent.index_h["intent_id"]
  end
end
