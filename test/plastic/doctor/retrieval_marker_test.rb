# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/doctor/retrieval_marker"

class DoctorRetrievalMarkerTest < Plastic::TestCase
  def folder = File.join(@plastic_home, "stores", "old")

  def problem = Plastic::Doctor::RetrievalMarker.new(@plastic_home, folder).problem

  def test_a_backfilled_store_has_no_problem
    Plastic::Graph.create(home: @plastic_home, store: "old")

    assert_nil problem
  end

  def test_a_knowledge_file_that_is_not_a_database_is_a_problem
    origin
    FileUtils.mkdir_p(folder)
    File.write(File.join(folder, "knowledge_graph.db"), "not a database")

    assert_equal Plastic::Doctor::RetrievalMarker::PROBLEM, problem
  end

  def test_an_empty_origin_file_is_a_problem
    Plastic::Graph.create(home: @plastic_home, store: "old")
    File.write(File.join(@plastic_home, "origin_id"), "\n")

    assert_equal Plastic::Doctor::RetrievalMarker::PROBLEM, problem
  end
end
