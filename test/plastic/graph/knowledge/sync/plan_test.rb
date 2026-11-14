# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncPlanTest < Plastic::TestCase
  Sync = Plastic::Graph::Knowledge::Sync
  Plan = Sync::Plan
  Print = Plastic::Graph::Prints::Print

  # Paths keyed to [file hash, recorded hash, rows hash]: a conflict, a hand edit, a row change and a level file.
  HASHES = { "c.md" => %w[f p r], "h.md" => %w[f p p], "r.md" => %w[p p r], "l.md" => ["x", nil, "x"] }.freeze

  def entries = HASHES.map { |path, (file, printed, rows)| Sync::Entry.new(path, file, printed, Print.new(path, :work, rows, nil)) }

  def plan(direction = :up, legacy: false, problem: nil, **options)
    Plan.new(resolution: Sync::Resolution.new(direction, "/root", options), entries:, legacy:, problem:, unreadable: [], archived: 0)
  end

  def paths(list) = list.map(&:path)

  # Which of the three hashes the entry lacks.
  def absent(entry) = [entry.file_sha, entry.printed_sha, entry.rows_sha].map(&:nil?)

  def test_each_entry_takes_the_action_of_its_direction
    assert_equal({ "c.md" => :conflict, "h.md" => :read, "r.md" => :none, "l.md" => :record },
      plan.actions.transform_keys(&:path))
    assert_equal [%w[r.md], %w[l.md], :down], [paths(plan(:down).taking(:print)), paths(plan(:down).taking(:record)), plan(:down).direction]
  end

  def test_conflicts_list_their_paths_until_an_overwrite_names_them
    assert_equal [%w[c.md], [], %w[c.md]], [plan.conflicts, plan(overwrite: nil).conflicts, plan(overwrite: "/root/h.md").conflicts]
    assert_equal [%w[c.md h.md], %w[c.md]], [paths(plan(overwrite: "/root/c.md").taking(:read)), paths(plan(:down, overwrite: "c.md").taking(:print)) - %w[r.md]]
  end

  def test_pending_counts_the_writes_and_a_legacy_import
    assert_equal [2, 3, 2], [plan.pending, plan(legacy: true).pending, plan(:down).pending]
  end

  def test_merging_follows_the_resolution
    assert_equal [false, true, true], [plan.merging?, plan(merge: true).merging?, plan(overwrite: "c.md").merging?]
  end

  def test_a_failure_names_the_problem_or_an_unknown_overwrite_path
    assert_equal ["held", "store/9.md names no file and no rows of this store", nil, nil],
      [plan(problem: "held").failure, plan(overwrite: "/root/store/9.md").failure, plan(overwrite: "c.md").failure, plan.failure]
  end

  # `shas` are the file's hash, the recorded hash and the rows' hash.
  def generated_plan(direction, path, *shas, **plan_options)
    file, printed, rows = shas
    entry = Sync::Entry.new(path, file, printed, rows ? Print.new(path, :work, rows, nil) : Sync::Entry::NO_PRINT)
    Plan.new(resolution: Sync::Resolution.new(direction, "/root", plan_options.delete(:options) || {}), entries: [entry], legacy: false, problem: nil, unreadable: [], archived: 0, **plan_options)
  end

  def action_of(plan) = plan.actions.values.first

  def test_a_generated_file_that_is_not_level_is_planned_for_a_print_up_when_it_has_rows_and_cannot_be_read
    index = generated_plan(:up, "store/index.json", "f", "p", "r", unreadable_files: { "store/index.json" => "not JSON" })
    context = generated_plan(:up, "store/1--alpha/context.json", "f", "p", "r")

    assert_equal [:print, :print], [action_of(index), action_of(context)]
  end

  def test_a_generated_index_that_can_be_read_is_planned_for_a_read_up
    assert_equal :read, action_of(generated_plan(:up, "store/index.json", "f", "p", "r"))
  end

  def test_a_generated_file_with_no_rows_is_left_alone_up
    assert_equal :none, action_of(generated_plan(:up, "store/1--alpha/context.json", "f", nil, nil))
  end

  def test_a_level_generated_file_is_left_alone_up
    assert_equal :none, action_of(generated_plan(:up, "store/index.json", "r", "r", "r"))
  end

  def test_a_file_that_cannot_be_read_is_planned_for_nothing_up_and_counts_no_pending_write
    plan = generated_plan(:up, "store/1--alpha/graph.json", "f", "p", "p", unreadable_files: { "store/1--alpha/graph.json" => "junk" })

    assert_equal [:none, 0], [action_of(plan), plan.pending]
  end

  def test_an_overwrite_of_one_path_prints_it_down_when_only_the_file_changed
    plan = generated_plan(:down, "h.md", "f", "p", "p", options: { overwrite: "h.md" })

    assert_equal :print, action_of(plan)
  end

  def test_a_bare_overwrite_prints_nothing_down_for_a_file_only_the_file_changed
    plan = generated_plan(:down, "h.md", "f", "p", "p", options: { overwrite: nil })

    assert_equal :none, action_of(plan)
  end

  def test_an_overwrite_of_one_path_leaves_another_path_alone_down
    plan = generated_plan(:down, "h.md", "f", "p", "p", options: { overwrite: "other.md" })

    assert_equal :none, action_of(plan)
  end

  def test_an_overwrite_of_one_path_with_no_rows_prints_nothing_down
    plan = generated_plan(:down, "h.md", "f", "p", nil, options: { overwrite: "h.md" })

    assert_equal :none, action_of(plan)
  end

  def test_build_marks_a_legacy_store_up_and_refuses_it_down
    write("INDEX.md", "# Index\n")
    build = ->(direction) { Plan.build(folder, retrieval, Sync::Resolution.new(direction, store_root, {})) }

    assert_equal [true, nil], build.call(:up).to_h.values_at(:legacy, :problem)
    assert_equal [false, "this store still has INDEX.md; run plastic sync up to import it first"],
      build.call(:down).to_h.values_at(:legacy, :problem)
  end

  def test_entries_join_the_prints_the_files_and_the_recorded_hashes
    open_intent
    write("store/1--alpha/spec.md", "# Spec\n")
    found = Plan.entries(folder, retrieval).to_h { |entry| [entry.path, absent(entry)] }

    assert_equal %w[store/1--alpha/graph.json store/1--alpha/intent.md store/1--alpha/savepoint.md store/1--alpha/spec.md
      store/index.json], found.keys
    assert_equal [[false, false, false], [false, true, true]], found.values_at("store/index.json", "store/1--alpha/spec.md")
  end

  def test_on_disk_lists_the_index_and_the_intent_files
    assert_empty Plan.on_disk(folder)
    open_intent

    assert_equal %w[store/index.json store/1--alpha/graph.json store/1--alpha/intent.md store/1--alpha/savepoint.md], Plan.on_disk(folder)
  end
end
