# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/restore_intent"

class RestoreIntentTest < Plastic::TestCase
  def restore(intent_id = "1") = run_workflow(Plastic::Workflows::RestoreIntent, intent_id:)

  def test_an_archived_intent_is_restored
    open_intent(status: "done")
    store_graphs.work.archive_intent("1")

    outcome, context = restore

    assert_equal [:done, ["intent: 1 restored"]], [outcome, context.printed]
    refute retrieval.archived?("1")
  end

  def test_an_intent_that_is_not_archived_fails_the_call
    open_intent

    assert_kind_of Plastic::Failed, restore.first
  end
end
