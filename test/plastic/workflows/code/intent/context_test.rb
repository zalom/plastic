# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/context"
require_relative "../../../../../lib/plastic/workflows/code/intent/discover"

class SubmitContextTest < Plastic::TestCase
  EMPTY = { "facts" => [], "interpretations" => [], "gaps" => [], "rulings" => [] }.freeze

  def setup
    super
    @reference = retrieval.reference("1", open_intent.file).fetch(:uri)
  end

  def discovered = run_workflow(Plastic::Workflows::Code::Intent::Discover, intent_id: "1", terms: "alpha", source_projects: [])

  def submit(submission)
    path = File.join(@home, "submission.json")
    File.write(path, submission.is_a?(String) ? submission : JSON.generate(submission))
    run_workflow(Plastic::Workflows::Code::Intent::Context, intent_id: "1", from: path)
  end

  def test_a_valid_submission_is_saved_and_printed
    discovered

    outcome, context = submit(EMPTY.merge("evidence" => [@reference]))

    assert_equal [:done, [@reference]], [outcome, printed_row(context, "context").fetch("evidence")]
  end

  def stored(column) = store_graphs.databases.fetch(:store).row("SELECT #{column} FROM retrieval_contexts WHERE intent_id = '1'")&.fetch(column)

  def test_the_saved_context_is_read_back_from_the_knowledge_database
    discovered

    _, context = submit(EMPTY.merge("evidence" => [@reference]))

    assert_equal printed_row(context, "context"), JSON.parse(stored("data"))
  end

  def test_the_same_submission_saved_again_leaves_the_stored_row_as_it_is
    discovered
    submit(EMPTY.merge("evidence" => [@reference]))
    store_graphs.databases.fetch(:store).transaction { |batch| batch.add("UPDATE retrieval_contexts SET updated_at = 'kept' WHERE intent_id = '1'") }

    submit(EMPTY.merge("evidence" => [@reference]))

    assert_equal "kept", stored("updated_at")
  end

  def test_a_submission_that_stops_at_a_gate_saves_nothing
    discovered

    submit(EMPTY.merge("evidence" => [@reference.sub("intent.md", "missing.md")]))

    assert_nil stored("data")
  end

  def test_the_save_is_a_step_and_no_read_of_the_workflow_saves
    steps = Plastic::Workflows::Code::Intent::Context.steps

    assert_equal ["save the submitted context"], steps.grep(Plastic::CodeWorkflow::Step).map(&:name)
    refute(steps.grep(Plastic::CodeWorkflow::Read).any? { |read| read.name.include?("persist") })
  end

  def test_a_submission_that_is_not_json_is_a_usage_error
    discovered

    assert_raises(Plastic::CLI::Command::Usage) { submit("not json") }
  end

  def test_a_submission_missing_a_category_is_a_usage_error
    discovered

    error = assert_raises(Plastic::CLI::Command::Usage) { submit({ "evidence" => [] }) }

    assert_includes error.message, "needs the arrays evidence, facts, interpretations, gaps and rulings"
  end

  def test_a_submission_without_a_discovery_is_a_usage_error
    assert_raises(Plastic::CLI::Command::Usage) { submit(EMPTY.merge("evidence" => [])) }
  end
end
