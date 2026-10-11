# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/cli/projects_file"
require_relative "../../../scripts/lib/plastic/workflows/retrieval_repair"

class RetrievalRepairTest < Plastic::TestCase
  Maintenance = Plastic::Graph::RetrievalGraph::MaintenanceRequired

  def problem(error) = Plastic::Workflows::RetrievalRepair.new(scoped_harness(slug: "global").scope).problem(error)

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
end
