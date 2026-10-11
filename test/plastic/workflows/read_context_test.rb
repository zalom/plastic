# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/read_context"
require_relative "../../../scripts/lib/plastic/workflows/context_persistence"

class ReadContextTest < Plastic::TestCase
  def read_context(intent_id = "1") = run_workflow(Plastic::Workflows::ReadContext, intent_id:)

  def test_a_saved_context_is_printed
    reference = retrieval.reference("1", open_intent.file).fetch(:uri)
    Plastic::Workflows::ContextPersistence.new(call_context(intent_id: "1")).persist({ "evidence" => [reference] })

    outcome, context = read_context

    assert_equal [:done, [reference]], [outcome, printed_row(context, "context").fetch("evidence")]
  end

  def test_an_intent_with_no_saved_context_fails_the_call
    open_intent

    assert_equal "code_read_context, gate: no retrieval context for intent 1", read_context.first.message
  end

  def test_a_store_with_no_backfill_marker_names_its_repair
    reference = retrieval.reference("1", open_intent.file).fetch(:uri)
    Plastic::Workflows::ContextPersistence.new(call_context(intent_id: "1")).persist({ "evidence" => [reference] })
    forget_backfill

    assert_includes read_context.first.message, "run plastic install --reinstall, then try again"
  end

  private

  def forget_backfill
    store_graphs.databases.fetch(:knowledge).transaction { |batch| batch.add("DELETE FROM retrieval_backfills") }
  end
end
