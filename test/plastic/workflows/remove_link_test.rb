# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/remove_link"

class WorkflowRemoveLinkTest < Plastic::TestCase
  def setup
    super
    open_intent
    open_intent("Beta")
    store_graphs.work.add_link(from_ref: "1", to_ref: "2", kind: "related")
  end

  def remove(kind) = run_workflow(Plastic::Workflows::RemoveLink, intent_id: "1", target: "2", kind:)

  def test_a_link_is_removed_and_named
    outcome, context = remove("related")

    assert_equal [:done, ["link: 1 related 2 removed"]], [outcome, context.printed]
    assert_empty retrieval.links("1")
  end

  def test_a_link_of_another_kind_fails_and_stays
    outcome, = remove("source")

    assert_equal "code_remove_link, gate: no source link from 1 to 2", outcome.message
    assert_equal 1, retrieval.links("1").size
  end
end
