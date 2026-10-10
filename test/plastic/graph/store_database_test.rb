# frozen_string_literal: true

require_relative "../../test_helper"

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
