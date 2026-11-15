# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/graph/resume"

class WorkflowResumeGraphTest < Plastic::TestCase
  Flow = Plastic::Workflows::Code::Graph::Resume

  def resume(stores: nil, slug: nil)
    context = Plastic::Context.new(declared: Flow.facts + [:stores], facts: { stores: }, graphs: {}, harness: scoped_harness(session: "s-1", slug:))
    [Flow.call(context), context]
  end

  def register(*slugs)
    entries = slugs.map { |slug| "  #{slug}:\n    path: #{Dir.mktmpdir}\n" }.join
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n#{entries}")
  end

  def test_a_store_with_an_open_intent_prints_its_rows_and_offers_the_command_that_runs_next
    open_intent
    outcome, context = resume

    assert_equal [:done, "global", "plastic auto 1"], [outcome, printed_row(context, "store:"), Flow.closing(outcome, context).first]
  end

  def test_a_store_with_no_work_offers_the_status
    outcome, context = resume

    assert_equal [:done, ["plastic status", "no store has open work"]], [outcome, Flow.closing(outcome, context)]
  end

  def test_a_store_that_is_not_registered_is_a_usage_error_naming_the_projects
    register("blog")
    error = assert_raises(Plastic::CLI::Command::Usage) { resume(stores: "nosuch") }

    assert_equal "no registered project named \"nosuch\"; the projects are blog", error.message
  end

  def test_no_store_name_after_stores_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { resume(stores: " , ") }

    assert_equal "name at least one store after --stores", error.message
  end

  def test_stores_and_a_project_together_are_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { resume(stores: "global", slug: "blog") }

    assert_equal "--stores names the stores; --project does not apply", error.message
  end

  def test_two_stores_with_work_name_the_first_in_the_because
    register("blog")
    Plastic::Graph.create(home: @plastic_home, store: "blog").work.then { |work| work.print_intent(work.write_intent(title: "Beta").intent_id) }
    open_intent
    outcome, context = resume(stores: "global,blog")

    assert_equal [:done, "store global is the first named with work; each then: line holds a store's own next command"], [outcome, Flow.closing(outcome, context).last]
  end
end
