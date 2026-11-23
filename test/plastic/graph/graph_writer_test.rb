# frozen_string_literal: true

require_relative "../../test_helper"

class GraphWriterTest < Plastic::TestCase
  fixtures :empty

  def work = store_graphs.work

  def run_session(graphs) = graphs.databases[:local].row("SELECT session_id FROM command_runs WHERE subject = 1").fetch("session_id")

  def test_write_intent_returns_the_intent_and_ignores_the_databases
    intent = work.write_intent(title: "Alpha")

    assert_equal %w[1 Alpha], [intent.intent_id, intent.title]
    assert_equal "*.db\n*.db-journal\nbackups/\n", folder.read(".gitignore")
  end

  def test_print_intent_prints_the_index_and_the_intent_files
    work.write_intent(title: "Alpha")

    assert_equal %w[store/index.json store/1--alpha/intent.md store/1--alpha/work.log store/1--alpha/graph.json],
      work.print_intent("1")
    assert_empty work.print_intent("1")
  end

  def test_intent_problem_and_ref_line_answer_for_the_store
    assert_equal ["no intent 9 in this store to be the parent", "ref: ENG-1"],
      [work.intent_problem(parent_id: "9"), work.ref_line("ENG-1")]
  end

  def test_the_backups_refuse_a_restore_while_a_live_claim_holds_a_node
    work.add_node(intent_id: "1", title: "Build")
    work.claim_node(intent_id: "1", id: "n1", by: "s-2")

    assert_predicate work.backups.restorer, :claimed?
  end

  def test_a_sync_plan_applies_through_the_graph_writer
    open_intent
    write("store/1--alpha/spec.md", "# Spec\n")
    plan = work.sync_plan(:up, {})

    assert_equal [:up, 1], [plan.direction, plan.pending]
    assert_equal ["read store/1--alpha/spec.md"], work.sync_apply(plan)
  end

  def test_a_sync_preview_changes_no_row_and_says_it_is_a_preview
    open_intent
    write("store/1--alpha/spec.md", "# Spec\n")

    run = work.preview_sync({})

    assert_equal ["preview: read store/1--alpha/spec.md"], run.lines.grep(/spec\.md/)
  end

  def test_print_intent_keeps_the_databases_out_of_versioning
    work.write_intent(title: "Alpha")
    folder.delete(".gitignore")
    work.print_intent("1")

    assert folder.exist?(".gitignore")
  end

  def test_a_second_session_rerunning_a_tool_moves_the_run_but_keeps_the_earlier_work_log_lines
    first = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1").work
    first.print_intent(first.write_intent(title: "Alpha").intent_id)
    second = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-2")
    second.work.save_command_run(Plastic::CommandRun.fresh("intent end", "1", FixedClock::AT))

    assert_equal "s-2", run_session(second)
    assert_equal "s-1", structure.work_log("1").first.session_id

  end

  def opened = yield(Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1"))

  def test_a_roadmap_file_is_readable_once_printed_and_not_before
    work.write_batch("r1", 1, fields: Plastic::Graph::Knowledge::Roadmap::Writer::Fields.new(title: "T", goal: "G", done: "d"))

    refute work.roadmap_file_readable?("r1")
    work.print_roadmap("r1")
    assert work.roadmap_file_readable?("r1")
  end

  def test_a_roadmap_file_in_an_older_form_is_not_readable
    folder.write("roadmaps/old.md", "not a roadmap form")

    refute work.roadmap_file_readable?("old")
  end

  def test_an_intent_archives_and_unarchives
    opened { |graphs| graphs.work.write_intent(title: "Alpha") }
    opened { |graphs| graphs.work.print_intent("1") }
    opened { |graphs| graphs.work.note_intent(graphs.retrieval.intent("1"), "note", "why it ends") }
    opened { |graphs| graphs.work.abandon_intent("1") }

    assert_equal [true, true], [opened { |graphs| graphs.work.archive_intent("1").first }, opened { |graphs| graphs.work.unarchive_intent("1").first }]
  end
end
