# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/plan"

class RepairPlanTest < Plastic::TestCase
  Plan = Plastic::Graph::Knowledge::Repair::Plan

  OLD = "store/7--old"
  OTHER = "store/8--other"
  FILES = {
    "7--old.md" => "# Old\n\nSee [the plan](plan.md).\n",
    "spec.md" => "# Spec\n\nSee [the intent](7--old.md) and [the review](review.rb).\n",
    "plan.md" => "# Plan\n",
    "checklist.md" => "- [x] one\n",
    "actions/a1.md" => "# A1\n",
    "review.rb" => "puts 1\n",
    "graph.md" => "# Graph\n",
    "delivery.write.lock" => "pid\n",
    "revisions.md" => "# revisions.md\n\n## Revision v1 - 2026-09-01\nWhy: a fix.\n"
  }.freeze

  def setup
    super
    @folder = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@home, "folder"))
    FILES.each { |rel, text| @folder.write("#{OLD}/#{rel}", text) }
    @folder.write("#{OTHER}/spec.md", "# Other\n\n[old plan](../7--old/plan.md)\n")
  end

  def plan(**options) = Plan.new(@folder, zone: "+00:00", **options)

  def moves(found = plan) = found.moves.map { |move| [move.from.delete_prefix("#{OLD}/"), move.to.delete_prefix("#{OLD}/")] }.sort

  def test_the_old_intent_file_is_renamed_and_the_old_files_move_where_the_layout_names
    assert_equal [%w[7--old.md intent.md], %w[actions/a1.md resources/references/actions/a1.md], %w[checklist.md resources/references/checklist.md],
      %w[plan.md resources/references/plan.md], %w[review.rb resources/tmp/review.rb]], moves
  end

  def test_graph_md_and_the_lock_files_are_removed
    assert_equal %W[#{OLD}/delivery.write.lock #{OLD}/graph.md], plan.removals.map(&:path).sort
  end

  def test_each_revision_becomes_an_amended_line_and_the_file_is_removed
    found = plan

    assert_equal [["7", "2026-09-01T00:00:00Z", "revisions.md v1: Why: a fix.; #{Plastic::Layout.amendment_reason(:revision)}"]],
      found.revisions.map { |line| [line.intent_id, line.at, line.text] }
    assert_equal ["#{OLD}/revisions.md"], found.revision_files
  end

  def test_an_open_intent_gets_no_amended_line_for_its_moves
    assert_equal [], plan.amendments.map(&:text) - plan.revisions.map(&:text)
  end

  def test_a_closed_intent_gets_one_amended_line_for_each_change_with_its_reason
    reason = ->(kind) { Plastic::Layout.amendment_reason(kind) }
    texts = plan(closed: Set["7"]).amendments.map(&:text)

    assert_includes texts, "renamed 7--old.md to intent.md; #{reason.call(:rename)}"
    assert_includes texts, "moved plan.md to resources/references/plan.md; #{reason.call(:move)}"
    assert_includes texts, "removed graph.md; #{reason.call(:remove)}"
    assert_includes texts, "spec.md: link 7--old.md -> intent.md; #{reason.call(:link)}"
    assert_includes texts, "intent.md: link plan.md -> resources/references/plan.md; #{reason.call(:link)}"
    assert_equal 5 + 2 + 1 + 3, texts.size
  end

  def test_a_link_in_another_closed_intent_to_a_moved_file_is_rewritten_and_amended
    found = plan(closed: Set["8"])

    assert_equal "# Other\n\n[old plan](../7--old/resources/references/plan.md)\n", found.rewrites.find { |rewrite| rewrite.path == "#{OTHER}/spec.md" }.text
    assert_equal ["spec.md: link ../7--old/plan.md -> ../7--old/resources/references/plan.md; #{Plastic::Layout.amendment_reason(:link)}"],
      found.amendments.select { |line| line.intent_id == "8" }.map(&:text)
  end

  def test_a_repair_of_one_intent_moves_only_its_files
    @folder.write("#{OTHER}/plan.md", "# Other plan\n")

    assert_equal [], plan(dirs: [OLD]).moves.map(&:from).grep(/8--other/)
  end

  def test_a_revisions_file_with_no_readable_entry_is_refused
    @folder.write("#{OLD}/revisions.md", "# Revisions\n\nNothing dated.\n")
    error = assert_raises(Plastic::Refused) { plan.revisions }

    assert_includes error.message, "#{OLD}/revisions.md"
  end

  def test_the_preview_names_every_change_and_writes_nothing
    before = snapshot(@folder.root)
    lines = plan(closed: Set["7"]).preview

    assert_includes lines, "preview: rename #{OLD}/7--old.md -> #{OLD}/intent.md"
    assert_includes lines, "preview: remove #{OLD}/graph.md"
    assert_includes lines, "preview: remove #{OLD}/revisions.md"
    assert(lines.any? { |line| line.start_with?("preview: would amend #{OLD}: revisions.md v1") })
    assert_equal before, snapshot(@folder.root)
  end

  def test_a_folder_in_the_layout_has_an_empty_plan
    clean = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@home, "clean"))
    clean.write("store/1--a/intent.md", "# A\n")
    clean.write("store/1--a/spec.md", "# Spec\n")
    clean.write("store/1--a/resources/references/plan.md", "# Plan\n")

    assert_predicate Plan.new(clean), :empty?
  end
end
