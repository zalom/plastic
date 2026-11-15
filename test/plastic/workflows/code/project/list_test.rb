# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/project/list"

class WorkflowListProjectsTest < Plastic::TestCase
  Flow = Plastic::Workflows::Code::Project::List

  def register(slug, path, store: true)
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  #{slug}:\n    path: #{path}\n")
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", slug)) if store
  end

  def test_with_none_registered_the_outcome_offers_to_register_one
    outcome, context = run_workflow(Flow)

    assert_equal [:none, "plastic project new SLUG PATH", []], [outcome, Flow.closing(outcome, context).first, printed_rows(context)]
  end

  def test_a_registered_project_is_printed_with_its_path
    register("blog", "/tmp/blog")

    outcome, context = run_workflow(Flow)

    assert_equal [:done, [["project", "blog: /tmp/blog"]]], [outcome, printed_rows(context)]
  end

  def test_a_project_with_no_store_folder_says_so_on_its_row
    register("blog", "/tmp/blog", store: false)

    assert_equal [["project", "blog: /tmp/blog (no store)"]], printed_rows(run_workflow(Flow).last)
  end

  def test_the_listed_outcome_offers_the_status
    register("blog", "/tmp/blog")

    outcome, context = run_workflow(Flow)

    assert_equal ["plastic status", "the projects are listed"], Flow.closing(outcome, context)
  end
end
