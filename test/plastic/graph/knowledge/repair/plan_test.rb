# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/plan"

# The store folder of a closed or open intent in the old layout, with a neighbor that links to its plan.
module RepairPlanFolder
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
    @folder.write("#{OTHER}/spec.md", "# Other\n\n[old review](../7--old/review.rb)\n")
  end

  def plan(**options) = Plan.new(@folder, zone: "+00:00", **options)

  def moves(found = plan) = found.moves.map { |move| [move.from.delete_prefix("#{OLD}/"), move.to.delete_prefix("#{OLD}/")] }.sort

  def closed_texts = plan(closed: Set["7"]).amendments.map(&:text)

  def reason(kind) = Plastic::Layout.amendment_reason(kind)

  def structural(found = plan(closed: Set["7"])) = found.amendments.reject { |line| line.text.match?(/\A(revisions\.md |\S+: link )/) }
end

class RepairPlanTest < Plastic::TestCase
  include RepairPlanFolder

  def test_the_old_intent_file_is_renamed_and_the_old_files_move_where_the_layout_names
    assert_equal [%w[7--old.md intent.md], %w[review.rb resources/tmp/review.rb]], moves
  end

  def test_graph_md_the_lock_files_and_the_rebuilt_files_are_removed
    assert_equal %W[actions/a1.md checklist.md delivery.write.lock graph.md plan.md].map { |rel| "#{OLD}/#{rel}" }, plan.removals.map(&:path).sort
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

  def test_a_closed_intent_gets_one_amended_line_for_its_structural_changes_and_one_for_each_link_and_revision
    assert_equal [1, 1 + 2 + 1], [structural.size, closed_texts.size]
  end

  def test_the_one_line_of_a_folder_lists_each_rename_move_and_removal_with_its_reason
    assert_equal ["renamed 7--old.md to intent.md (#{reason(:rename)}); moved review.rb to resources/tmp/review.rb (#{reason(:move)}); " \
                  "removed delivery.write.lock, graph.md, revisions.md (#{reason(:remove)}); " \
                  "rebuilt actions/a1.md, checklist.md, plan.md (#{reason(:rebuild)})"], structural.map(&:text)
  end

  def test_the_line_of_a_folder_has_the_time_of_the_repair_and_names_no_file
    assert_equal [["7", "", nil]], structural.map { |line| [line.intent_id, line.path, line.at] }
  end

  def test_an_empty_gitkeep_is_removed_and_not_moved
    @folder.write("#{OLD}/actions/.gitkeep", "")
    found = plan(closed: Set["7"])

    assert_equal [false, true], [found.moves.map(&:inside_from).include?("actions/.gitkeep"), found.removals.map(&:inside).include?("actions/.gitkeep")]
    assert_includes structural(found).first.text, "rebuilt actions/.gitkeep, actions/a1.md, checklist.md, plan.md"
  end

  def test_an_actions_folder_that_held_only_an_empty_gitkeep_is_a_removal_alone
    @folder.delete("#{OLD}/actions/a1.md")
    @folder.write("#{OLD}/actions/.gitkeep", "")

    refute_match(/(\A|; )moved actions\//, structural.first.text)
  end

  def test_each_link_rewritten_in_a_core_file_of_a_closed_intent_gives_its_reason
    assert_equal ["spec.md: link 7--old.md -> intent.md; #{reason(:link)}"], closed_texts.grep(/: link (plan\.md|7--old\.md) /).sort
  end

  def test_a_link_in_another_closed_intent_to_a_moved_file_is_rewritten_and_amended
    found = plan(closed: Set["8"])

    assert_equal "# Other\n\n[old review](../7--old/resources/tmp/review.rb)\n", found.rewrites.find { |rewrite| rewrite.path == "#{OTHER}/spec.md" }.text
    assert_equal ["spec.md: link ../7--old/review.rb -> ../7--old/resources/tmp/review.rb; #{Plastic::Layout.amendment_reason(:link)}"],
      found.amendments.select { |line| line.intent_id == "8" }.map(&:text)
  end

  def test_a_repair_of_one_intent_moves_only_its_files
    @folder.write("#{OTHER}/plan.md", "# Other plan\n")

    assert_equal [], plan(dirs: [OLD]).moves.map(&:from).grep(/8--other/)
  end

  def test_a_repair_of_one_intent_still_amends_the_link_a_closed_neighbor_has_to_a_moved_file
    found = plan(dirs: [OLD], closed: Set["8"])

    assert_equal ["spec.md: link ../7--old/review.rb -> ../7--old/resources/tmp/review.rb; #{Plastic::Layout.amendment_reason(:link)}"],
      found.amendments.select { |line| line.intent_id == "8" }.map(&:text)
  end

  def test_a_repair_of_one_intent_lists_only_its_own_links_left_as_they_are
    @folder.write("#{OLD}/spec.md", "# Spec\n\n[gone](missing.md)\n")
    left = ->(dirs) { plan(dirs:, links_left: true).preview.grep(/\Apreview: link left as it is/) }

    assert_equal [["preview: link left as it is #{OLD}/spec.md: missing.md"], []], [left.call([OLD]), left.call([OTHER])]
  end

  def test_a_revisions_file_with_no_readable_entry_is_refused
    @folder.write("#{OLD}/revisions.md", "# Revisions\n\nNothing dated.\n")
    error = assert_raises(Plastic::Refused) { plan.revisions }

    assert_includes error.message, "#{OLD}/revisions.md"
  end
end

# The preview and the report of a plan: one line for each intent folder, and the totals.
class RepairPlanPreviewTest < Plastic::TestCase
  include RepairPlanFolder

  def test_the_preview_prints_one_line_for_each_folder_it_changes
    lines = plan(closed: Set["7"]).preview

    assert_equal ["preview: would amend #{OLD}: #{structural.first.text}"], lines.grep(/\Apreview: would amend #{OLD}: renamed/)
    assert_equal [], lines.grep(/\Apreview: (rename|move|remove) /)
    assert(lines.any? { |line| line.start_with?("preview: would amend #{OLD}: revisions.md v1") })
  end

  def test_the_preview_of_an_open_intent_names_the_repair_of_its_folder
    assert_equal 1, plan.preview.grep(/\Apreview: would repair #{OLD}: renamed 7--old\.md to intent\.md /).size
  end

  def test_the_preview_counts_the_folders_and_the_changes_apart
    @folder.write("#{OLD}/spec.md", "# Spec\n\n[gone](missing.md) [the intent](7--old.md)\n")

    assert_equal "preview: 1 intent folder, 8 changes (1 rename, 1 move, 3 removals, 3 rebuilds); 2 links changed; 3 amended lines; " \
                 "1 link left as it is, which --links-left lists", plan(closed: Set["7"]).preview.last
  end

  def test_the_links_left_as_they_are_print_only_as_a_count_unless_asked
    @folder.write("#{OLD}/spec.md", "# Spec\n\n[gone](missing.md)\n")
    left = ->(**options) { plan(**options).preview.grep(/\Apreview: link left as it is/) }

    assert_equal [[], ["preview: link left as it is #{OLD}/spec.md: missing.md"]], [left.call, left.call(links_left: true)]
  end

  def test_the_report_of_a_repair_prints_the_same_folder_lines_and_totals
    found = plan(closed: Set["7"])

    assert_equal ["repaired: #{found.preview.last.delete_prefix("preview: ")}", "amended #{OLD}: #{structural.first.text}"],
      found.report.values_at(0, 1)
  end

  def test_the_preview_writes_nothing
    before = snapshot(@folder.root)
    plan(closed: Set["7"]).preview

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
