# frozen_string_literal: true

require_relative "../test_helper"

class GraphTest < Plastic::TestCase
  def graphs(store = "plastic") = Plastic::Graph.open(home: @plastic_home, store:)

  def closed_run(subject = "7")
    Plastic::RoutineRun.fresh("intent end", subject).advance(:code_a, :code_b)
      .close(Plastic::Finished.new(next_command: "plastic next", because: "done"), { id: "7", list: [1, 2] })
  end

  def test_a_saved_routine_run_reads_back_the_same
    run = closed_run
    graphs.work.save_routine_run(run)

    assert_equal run.to_h, graphs.retrieval.routine_run("intent end", "7").to_h
  end

  def test_a_routine_run_with_no_subject_reads_back_with_nil
    graphs.work.save_routine_run(closed_run(nil))

    assert_nil graphs.retrieval.routine_run("intent end", nil).subject
  end

  def test_a_second_save_updates_the_one_row
    run = Plastic::RoutineRun.fresh("intent end", "7")
    graphs.work.save_routine_run(run)
    graphs.work.save_routine_run(run.advance(:code_a, :code_b))

    assert_equal :code_b, graphs.retrieval.routine_run("intent end", "7").at
  end

  def test_no_row_reads_as_nil
    assert_nil graphs.retrieval.routine_run("intent end", "7")
  end

  def test_a_routine_run_belongs_to_its_store
    graphs("plastic").work.save_routine_run(closed_run)

    assert_nil graphs("global").retrieval.routine_run("intent end", "7")
  end

  def test_saving_a_routine_run_is_kept_off_the_report
    opened = graphs
    run = opened.work.save_routine_run(closed_run)

    assert_equal "7", run.subject
    assert_empty opened.wrote
  end

  def test_wrote_has_one_phrase_per_database_written
    opened = graphs
    opened.databases[:local].transaction { |batch| batch.insert(:routine_runs, { store: "plastic", tool: "x", subject: "" }) }

    assert_equal ["1 routine run in local.db"], opened.wrote
  end

  def test_wrote_says_the_rename_first
    machine = File.join(@home, "machine")
    Plastic::Graph::Database.new(File.join(machine, "home.db"), Plastic::Graph::Schema.fetch(:local)).rows("SELECT 1")
    Plastic::Graph::Database::ConnectionPool.release(machine)
    opened = Plastic::Graph.open(home: machine, store: "plastic")
    opened.databases[:local].transaction { |batch| batch.insert(:routine_runs, { store: "plastic", tool: "x", subject: "" }) }

    assert_equal ["home.db renamed to local.db", "1 routine run in local.db"], opened.wrote
  end

  def test_a_session_given_at_open_stamps_the_routine_run_row
    opened = Plastic::Graph.open(home: @plastic_home, store: "plastic", session: "s-1")
    opened.work.save_routine_run(closed_run)

    row = opened.databases[:local].row("SELECT session_id FROM routine_runs WHERE tool = 'intent end' AND subject = '7'")

    assert_equal "s-1", row.fetch("session_id")
  end
end
