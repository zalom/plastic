# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/link"

class AddLinkTest < Plastic::TestCase
  def setup
    super
    open_intent
    open_intent("Beta")
  end

  def link(target, kind: "cites") = run_workflow(Plastic::Workflows::Code::Intent::Link, intent_id: "1", target:, kind:)

  def test_a_link_is_written_and_named
    outcome, context = link("2")

    assert_equal [:done, ["link: 1 cites 2"]], [outcome, context.printed]
    assert_equal [%w[cites 2]], retrieval.links("1").map { |row| [row.kind, row.to_ref] }
  end

  def test_a_missing_target_fails_with_no_link
    assert_raises(Plastic::Failed) { link("9") }
    assert_empty retrieval.links("1")
  end

  def test_a_self_link_is_refused
    assert_raises(Plastic::Refused) { link("1") }
    assert_empty retrieval.links("1")
  end

  def test_a_repeated_link_is_refused_with_one_row_left
    link("2")

    assert_raises(Plastic::Refused) { link("2") }
    assert_equal 1, retrieval.links("1").size
  end
end
