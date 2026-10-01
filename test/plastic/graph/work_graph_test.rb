# frozen_string_literal: true

require_relative "../../test_helper"

class WorkGraphTest < Plastic::TestCase
  def work = store_graphs.work

  def test_write_intent_returns_the_intent_and_ignores_the_databases
    intent = work.write_intent(title: "Alpha")

    assert_equal %w[1 Alpha], [intent.intent_id, intent.title]
    assert_equal "*.db\n*.db-journal\n", folder.read(".gitignore")
  end

  def test_print_intent_prints_the_index_and_the_intent_files
    work.write_intent(title: "Alpha")

    assert_equal %w[store/index.json store/1--alpha/1--alpha.md store/1--alpha/savepoint.md store/1--alpha/graph.json],
      work.print_intent("1")
    assert_empty work.print_intent("1")
  end

  def test_intent_problem_and_ref_line_answer_for_the_store
    assert_equal ["no intent 9 in this store to be the parent", "ref: ENG-1"],
      [work.intent_problem(parent_id: "9"), work.ref_line("ENG-1")]
  end

  def test_a_sync_plan_applies_through_the_work_graph
    open_intent
    write("store/1--alpha/spec.md", "# Spec\n")
    plan = work.sync_plan(:up, {})

    assert_equal [:up, 1], [plan.direction, plan.pending]
    assert_equal ["read store/1--alpha/spec.md"], work.sync_apply(plan)
  end

  def test_print_intent_keeps_the_databases_out_of_versioning
    work.write_intent(title: "Alpha")
    folder.delete(".gitignore")
    work.print_intent("1")

    assert folder.exist?(".gitignore")
  end
end
