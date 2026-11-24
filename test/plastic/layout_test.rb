# frozen_string_literal: true

require_relative "../test_helper"
require "plastic/layout"

class LayoutTest < Plastic::TestCase
  def test_the_layout_file_has_no_problem
    assert_empty Plastic::Layout.problems
  end

  def test_each_core_file_has_a_name_by_its_role
    names = %i[intent spec outcome graph log context].map { |role| Plastic::Layout.name(role) }

    assert_equal %w[intent.md spec.md outcome.md graph.json work.log context.json], names
  end

  def test_a_file_names_its_purpose_its_writer_and_the_states_that_require_it
    spec = Plastic::Layout.file(:spec)

    assert_equal [%w[open done], "agent"], [spec.required, spec.writer]
    refute_empty spec.purpose
  end

  def test_a_file_is_required_only_in_the_states_its_entry_lists
    assert_equal %w[intent.md graph.json work.log], Plastic::Layout.required_in("abandoned").map(&:name)
  end

  def test_a_core_file_is_found_by_its_path_and_a_stray_is_not
    assert_equal [true, false], [Plastic::Layout.core?("spec.md"), Plastic::Layout.core?("notes.md")]
  end

  def test_the_new_intent_file_takes_its_front_matter_and_headings_from_the_layout
    assert_equal %w[id intent parent ref origin created], Plastic::Layout.file(:intent).front_matter
    assert_equal %w[Intent Context Outcome Insights], Plastic::Layout.file(:intent).headings.map(&:name)
  end

  def test_a_heading_lists_its_older_names
    done = Plastic::Layout.file(:spec).headings.find { |heading| heading.name == "Done criteria" }

    assert_equal ["Done criteria", "Acceptance Criteria", "Acceptance"], done.names
  end

  def test_the_four_resource_folders_are_named_by_role
    paths = %i[reports files references tmp].map { |role| Plastic::Layout.resource(role) }

    assert_equal %w[resources/output/reports/ resources/output/files/ resources/references/ resources/tmp/], paths
    assert_equal paths.first(2), Plastic::Layout.output_folders
  end

  def test_a_slug_takes_six_words
    assert_equal 6, Plastic::Layout.slug_words
  end

  def test_a_folder_name_joins_the_id_and_the_slug
    assert_equal "12a--one-two", Plastic::Layout.folder_name("12a", "one-two")
  end

  def test_a_legacy_path_finds_its_entry_and_its_sync
    found = %w[plan.md actions/ACTION_1.md revisions.md 3--old-name.md].map { |rel| Plastic::Layout.legacy_for(rel)&.sync }

    assert_equal %w[legacy_rows legacy_rows report document], found
  end

  def test_a_file_the_layout_does_not_name_has_no_legacy_entry
    assert_nil Plastic::Layout.legacy_for("my-notes.md")
  end

  def test_a_legacy_entry_names_its_repair_and_where_the_file_goes
    packets = Plastic::Layout.legacy_for("packets/one.json")

    assert_equal ["move", "resources/tmp/packets/"], [packets.repair, packets.to]
  end

  def test_a_file_that_moves_lands_under_the_target_of_its_entry
    assert_equal "resources/references/sources/a.md", Plastic::Layout.destination("resources/sources/a.md")
    assert_equal "resources/tmp/reviews/r.md", Plastic::Layout.destination("reviews/r.md")
  end

  def test_the_store_root_lists_what_it_may_hold_and_each_old_name_with_its_repair
    assert_includes Plastic::Layout.store_root_allowed.map(&:name), "backups/"
    assert_equal "remove", Plastic::Layout.store_root_legacy.find { |entry| entry.name == ".sessions/" }.repair
  end

  def with_legacy(**fields)
    data = Marshal.load(Marshal.dump(Plastic::Layout.data))
    data["legacy"] = [{ "name" => "x", "match" => ["x"], "sync" => "skip", "repair" => "remove", "why" => "w" }.merge(fields.transform_keys(&:to_s))]
    Plastic::Layout::Problems.new(data).to_a
  end

  def test_a_legacy_entry_with_an_unknown_sync_or_repair_is_a_problem
    assert_equal ["legacy entry x has the unknown sync nap", "legacy entry x has the unknown repair burn"], with_legacy(sync: "nap", repair: "burn")
  end

  def test_a_legacy_entry_that_moves_with_no_target_is_a_problem
    assert_equal ["legacy entry x moves with no target"], with_legacy(repair: "move")
  end

  def test_a_legacy_entry_that_moves_to_a_file_keeps_no_part_of_the_path
    entry = Plastic::Layout::LegacyEntry.new(name: "x.md", match: ["x.md"], sync: "skip", repair: "move", to: "resources/tmp/y.md", why: "w")

    assert_equal ["resources/tmp/y.md", nil], [entry.destination("x.md"), entry.with(repair: "remove").destination("x.md")]
  end

  def test_a_file_that_moves_to_a_folder_keeps_its_name
    assert_equal "resources/references/plan.md", Plastic::Layout.destination("plan.md")
  end
end
