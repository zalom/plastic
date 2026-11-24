# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/resources/sort"
require_relative "../../../../test_helpers/resources_homes"

class ResourcesSortPlanTest < Plastic::TestCase
  include ResourcesHomes

  SortPlan = Plastic::Graph::Knowledge::Resources::SortPlan

  def setup
    super
    @folder = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@home, "folder"))
  end

  def put(files) = files.each { |rel, text| @folder.write("#{INTENT}/#{rel}", text) }

  def test_plans_the_moves_of_a_store_in_the_old_layout
    put(OLD_FILES)
    plan = SortPlan.new(@folder)

    assert_equal MOVES.to_a.map { |from, to| ["#{INTENT}/#{from}", "#{INTENT}/#{to}"] }.sort, plan.moves.map { |move| [move.from, move.to] }.sort
    refute_predicate plan, :empty?
  end

  def test_a_sorted_store_has_an_empty_plan
    put(MOVES.values.to_h { |rel| [rel, "x\n"] }.merge("spec.md" => "# Spec\n"))

    assert_predicate SortPlan.new(@folder), :empty?
  end

  def test_a_target_with_other_bytes_is_refused
    put("reviews/r1.md" => "old\n", "resources/tmp/reviews/r1.md" => "other\n")
    error = assert_raises(Plastic::Refused) { SortPlan.new(@folder).moves }

    assert_includes error.message, "#{INTENT}/resources/tmp/reviews/r1.md"
  end

  def test_a_target_with_the_same_bytes_is_a_move_that_replaces_it
    put("reviews/r1.md" => "same\n", "resources/tmp/reviews/r1.md" => "same\n")

    assert_equal ["#{INTENT}/reviews/r1.md"], SortPlan.new(@folder).moves.map(&:from)
  end

  def test_the_links_of_the_moved_files_are_rewritten_and_the_ones_that_never_resolved_are_named
    put(OLD_FILES)
    plan = SortPlan.new(@folder)

    assert_equal ["#{INTENT}/resources/notes.md: missing.md"], plan.unresolved
    assert_equal %w[reviews/r1.md resources/notes.md spec.md].map { |rel| "#{INTENT}/#{MOVES.fetch(rel, rel)}" }.sort, plan.rewrites.map(&:path).sort
  end

  def test_links_that_leave_the_intent_folder_are_recomputed
    put(OLD_FILES.merge("reviews/r1.md" => "[o](../../2--b/spec.md) [m](../../2--b/reviews/r2.md)\n"))
    @folder.write("store/2--b/spec.md", "# B\n")
    @folder.write("store/2--b/reviews/r2.md", "# R2\n")
    plan = SortPlan.new(@folder)
    written = plan.rewrites.find { |rewrite| rewrite.path == "#{INTENT}/resources/tmp/reviews/r1.md" }

    assert_equal ["[o](../../../../2--b/spec.md) [m](../../../../2--b/resources/tmp/reviews/r2.md)\n", []], [written.text, plan.unresolved.grep(/r1/)]
  end
end
