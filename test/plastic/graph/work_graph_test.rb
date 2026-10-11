# frozen_string_literal: true

require_relative "../../test_helper"

class WorkGraphTest < Plastic::TestCase
  def work = store_graphs.work

  def run_session(graphs) = graphs.databases[:local].row("SELECT session_id FROM routine_runs WHERE subject = 1").fetch("session_id")

  def test_write_intent_returns_the_intent_and_ignores_the_databases
    intent = work.write_intent(title: "Alpha")

    assert_equal %w[1 Alpha], [intent.intent_id, intent.title]
    assert_equal "*.db\n*.db-journal\n", folder.read(".gitignore")
  end

  def test_print_intent_prints_the_index_and_the_intent_files
    work.write_intent(title: "Alpha")

    assert_equal %w[store/index.json store/1--alpha/intent.md store/1--alpha/savepoint.md store/1--alpha/graph.json],
      work.print_intent("1")
    assert_empty work.print_intent("1")
  end

  def test_intent_problem_and_ref_line_answer_for_the_store
    assert_equal ["no intent 9 in this store to be the parent", "ref: ENG-1"],
      [work.intent_problem(parent_id: "9"), work.ref_line("ENG-1")]
  end

  def test_the_backups_refuse_a_restore_while_a_live_lock_holds_an_intent
    work.take_lock("1", session_id: "s-2", mode: "auto")

    assert_predicate work.backups.restorer, :locked?
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

  def test_a_second_session_rerunning_a_tool_moves_the_run_but_keeps_the_earlier_savepoint_lines
    first = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1").work
    first.print_intent(first.write_intent(title: "Alpha").intent_id)
    second = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-2")
    second.work.save_routine_run(Plastic::RoutineRun.fresh("intent end", "1"))

    assert_equal "s-2", run_session(second)
    assert_equal "s-1", second.retrieval.savepoints("1").first.session_id
  end
end
