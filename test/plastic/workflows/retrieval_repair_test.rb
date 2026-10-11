# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/cli/projects_file"
require_relative "../../../scripts/lib/plastic/workflows/retrieval_repair"

class RetrievalRepairTest < Plastic::TestCase
  Maintenance = Plastic::Graph::RetrievalGraph::MaintenanceRequired

  def problem(error) = Plastic::Workflows::RetrievalRepair.new(scoped_harness(slug: "global").scope, error).problem

  def refusal(slug) = Maintenance.new("retrieval maintenance is required before source #{slug} can be read", slug:)

  def test_a_project_store_names_project_new_with_its_folder
    folder = File.join(@home, "my blog")
    Plastic::CLI::ProjectsFile.new(File.join(@plastic_home, "projects.yml")).add("blog", folder)

    assert_equal "retrieval maintenance is required before source blog can be read; run plastic project new blog #{Shellwords.escape(folder)}, then try again",
      problem(refusal("blog"))
  end

  def test_the_global_store_names_the_reinstall
    assert_equal "retrieval maintenance is required before source global can be read; run plastic install --reinstall, then try again",
      problem(refusal("global"))
  end

  def test_an_unregistered_store_names_project_new_with_a_path_placeholder
    assert_equal "retrieval maintenance is required before source loose can be read; run plastic project new loose PATH, then try again",
      problem(refusal("loose"))
  end

  def test_another_error_keeps_its_message
    assert_equal "no document", problem(Plastic::Graph::RetrievalGraph::MissingReference.new("no document"))
  end

  def test_a_check_of_maintained_stores_finds_no_problem
    Plastic::Graph.create(home: @plastic_home, store: "ready")

    assert_nil check(["ready"])
  end

  def test_a_check_names_the_repair_of_a_store_with_no_backfill_marker
    store_graphs.databases.fetch(:knowledge).transaction { |batch| batch.add("DELETE FROM retrieval_backfills") }

    assert_equal "retrieval maintenance is required before source global can be read; run plastic install --reinstall, then try again", check(["global"])
  end

  private

  def check(slugs) = Plastic::Workflows::RetrievalRepair.check(scoped_harness(slug: "global").scope, slugs)
end
