# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/archive_intent"

class ArchiveIntentTest < Plastic::TestCase
  def archive(intent_id = "1") = run_workflow(Plastic::Workflows::ArchiveIntent, intent_id:)

  def test_a_done_intent_is_archived_and_its_rows_stay
    open_intent(status: "done")

    outcome, context = archive

    assert_equal [:done, ["intent: 1 archived"]], [outcome, context.printed]
    assert retrieval.archived?("1")
    refute_nil retrieval.intent("1")
  end

  def test_an_open_intent_is_not_archived
    open_intent

    outcome, = archive

    refute_equal :done, outcome
    refute retrieval.archived?("1")
  end

  def test_an_unknown_intent_is_not_archived
    outcome, = archive("9")

    refute_equal :done, outcome
    refute retrieval.archived?("9")
  end
end
