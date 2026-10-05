# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeBackupDatabasesTest < Plastic::TestCase
  Databases = Plastic::Graph::Knowledge::Backup::Databases

  def test_no_list_means_no_choice
    assert_nil Databases.parse(nil)
  end

  def test_a_comma_list_names_each_database
    assert_equal %w[work_graph references], Databases.parse("work_graph,references")
  end

  def test_a_repeated_name_counts_once
    assert_equal %w[work_graph], Databases.parse("work_graph,work_graph")
  end

  def test_an_unknown_name_is_refused_and_named
    error = assert_raises(Databases::Unknown) { Databases.parse("work_graph,nope") }

    assert_includes error.message, "nope"
  end

  def test_the_goal_is_full_when_every_database_is_chosen
    assert_equal "full", Databases.goal(Databases.all.reverse)
  end

  def test_the_goal_lists_the_files_of_a_partial_choice
    assert_equal "partial:work_graph.db,references.db", Databases.goal(%w[work_graph references])
  end
end
