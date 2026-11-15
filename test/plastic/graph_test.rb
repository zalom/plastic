# frozen_string_literal: true

require_relative "../test_helper"

class GraphTest < Plastic::TestCase
  def graphs(store = "plastic") = Plastic::Graph.create(home: @plastic_home, store:)

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

  def test_saving_a_routine_run_is_left_out_of_the_report
    opened = graphs
    run = opened.work.save_routine_run(closed_run)

    assert_equal "7", run.subject
    assert_empty opened.wrote
  end

  def test_wrote_leaves_out_a_database_that_only_kept_a_routine_run
    opened = graphs
    opened.databases[:local].transaction { |batch| batch.insert(:routine_runs, { store: "plastic", tool: "x", subject: "" }) }

    assert_empty opened.wrote
  end

  def test_wrote_says_the_rename_first
    machine = File.join(@home, "machine")
    Plastic::Graph::Database.new(File.join(machine, "home.db"), Plastic::Graph::Schema.fetch(:local)).rows("SELECT 1")
    Plastic::Graph::Database::ConnectionPool.release(machine)
    opened = Plastic::Graph.create(home: machine, store: "plastic")
    opened.databases[:local].transaction { |batch| batch.insert(:routine_runs, { store: "plastic", tool: "x", subject: "" }) }

    assert_equal ["home.db renamed to local.db"], opened.wrote
  end

  def test_a_session_given_at_open_stamps_the_routine_run_row
    opened = Plastic::Graph.create(home: @plastic_home, store: "plastic", session: "s-1")
    opened.work.save_routine_run(closed_run)

    row = opened.databases[:local].row("SELECT session_id FROM routine_runs WHERE tool = 'intent end' AND subject = '7'")

    assert_equal "s-1", row.fetch("session_id")
  end
end

class StoreDatabaseTest < Plastic::TestCase
  def test_creating_a_store_makes_the_store_files
    Plastic::Graph.create(home: @plastic_home, store: "fresh").work.write_intent(title: "Alpha")

    assert_equal %w[knowledge_graph.db references.db work_graph.db], Dir.children(File.join(@plastic_home, "stores", "fresh")).grep(/\.db\z/).sort
  end

  def test_the_databases_sit_in_the_store_folder
    databases = store_graphs.databases

    assert_equal File.join(@plastic_home, "local.db"), databases[:local].path
    %i[work knowledge references].zip(%w[work_graph.db knowledge_graph.db references.db]).each do |key, file|
      assert_equal store_path(file), databases[key].path
    end
  end

  def test_the_store_folder_ignores_its_databases
    store_graphs.work.write_intent(title: "Alpha")

    assert_includes File.readlines(store_path(".gitignore"), chomp: true), "*.db"
  end

  def test_a_second_write_adds_no_second_ignore_line
    2.times { |n| store_graphs.work.write_intent(title: "Alpha #{n}") }

    assert_equal 1, File.readlines(store_path(".gitignore"), chomp: true).count("*.db")
  end

  def test_no_store_table_has_a_store_column
    store_graphs.work.write_intent(title: "Alpha")
    databases = store_graphs.databases.slice(:work, :knowledge, :references).values
    columns = databases.flat_map do |database|
      tables = database.rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
      tables.flat_map { |table| database.rows("SELECT name FROM pragma_table_info(:table)", table: table["name"]) }
    end

    refute_includes columns.map { |column| column["name"] }, "store"
  end

  def retrieval_schema(graphs) = graphs.databases.fetch(:knowledge).rows("SELECT name, version, completed_at FROM retrieval_schema")

  def test_opening_a_knowledge_database_records_its_retrieval_schema_version_without_completing_it
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "opened"))

    assert_equal [{ "name" => "retrieval", "version" => 1, "completed_at" => nil }],
      retrieval_schema(Plastic::Graph.open(home: @plastic_home, store: "opened"))
  end

  def test_a_store_made_by_create_has_its_retrieval_backfill_complete
    assert_equal [{ "name" => "retrieval", "version" => 1, "completed_at" => "complete" }],
      retrieval_schema(Plastic::Graph.create(home: @plastic_home, store: "made"))
  end
end
