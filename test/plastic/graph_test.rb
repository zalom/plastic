# frozen_string_literal: true

require_relative "support/kernel"

class GraphTest < Minitest::Test
  def setup = @home = Dir.mktmpdir("plastic-graph")

  def teardown = FileUtils.remove_entry(@home)

  def graphs(store = "plastic") = Plastic::Graph.open(home: @home, store:)

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
    opened.databases[:work].transaction { |batch| batch.insert(:routine_runs, { store: "plastic", tool: "x", subject: "" }) }

    assert_equal ["1 routine run in work_graph.db"], opened.wrote
  end
end
