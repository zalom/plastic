# frozen_string_literal: true

require_relative "whole_home"
require_relative "../../../scripts/lib/plastic/doctor"

class DoctorDatabaseCheckTest < Plastic::TestCase
  include WholeHome

  def path = File.join(@home, "checked", "work_graph.db")

  def problem = Plastic::Doctor::DatabaseCheck.new(path, :work).problem

  def test_a_database_with_every_declared_table_has_no_problem
    database(path, :work)

    assert_nil problem
  end

  def test_a_missing_file_is_named_and_stays_missing
    assert_equal ["#{path} is missing", false], [problem, File.exist?(path)]
  end

  def test_each_missing_table_is_named
    database(path, :work)
    drop_table(path, "intents")
    drop_table(path, "nodes")

    assert_equal "work_graph.db lacks the tables intents, nodes", problem
  end

  def test_a_database_lacking_only_a_new_table_passes_with_a_note
    knowledge = File.join(@home, "checked", "knowledge_graph.db")
    database(knowledge, :knowledge)
    drop_table(knowledge, "legacy_intents_data")
    check = Plastic::Doctor::DatabaseCheck.new(knowledge, :knowledge)

    assert_nil check.problem
    assert_equal "knowledge_graph.db lacks the table legacy_intents_data; the next open creates it", check.note
  end

  def test_a_database_lacking_a_new_table_and_an_old_one_names_only_the_old_one
    knowledge = File.join(@home, "checked", "knowledge_graph.db")
    database(knowledge, :knowledge)
    drop_table(knowledge, "legacy_intents_data")
    drop_table(knowledge, "documents")

    assert_equal "knowledge_graph.db lacks the table documents", Plastic::Doctor::DatabaseCheck.new(knowledge, :knowledge).problem
  end

  def test_a_file_that_is_not_a_database_is_named
    write(path, "not a database at all, just text that fills the header\n" * 4)

    assert_match(/\Awork_graph\.db cannot be read: /, problem)
  end
end
