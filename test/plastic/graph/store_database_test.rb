# frozen_string_literal: true

require_relative "../support/kernel"

class StoreDatabaseTest < Minitest::Test
  include KernelFixtures::StoreGraphs

  def test_a_write_through_the_sqlite3_program_makes_the_store_files
    Plastic::Graph.open(home: @plastic_home, store: "global").work.write_intent(title: "Alpha")

    assert_equal %w[knowledge_graph.db work_graph.db], Dir.children(store_root).grep(/\.db\z/).sort
  end

  def test_the_databases_sit_in_the_store_folder
    databases = store_graphs.databases

    assert_equal File.join(@plastic_home, "home.db"), databases[:home].path
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
end
