# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/add_link"

class AddLinkTest < Plastic::TestCase
  def setup
    super
    open_intent
    open_intent("Beta")
  end

  def link(target, kind: "cites") = run_workflow(Plastic::Workflows::AddLink, intent_id: "1", target:, kind:)

  def test_a_link_is_written_and_named
    outcome, context = link("2")

    assert_equal [:done, ["link: 1 cites 2"]], [outcome, context.printed]
    assert_equal [%w[cites 2]], retrieval.links("1").map { |row| [row.kind, row.to_ref] }
  end

  def test_a_missing_target_fails_with_no_link
    outcome, = link("9")

    assert_kind_of Plastic::Failed, outcome
    assert_empty retrieval.links("1")
  end

  def test_a_self_link_is_refused
    outcome, = link("1")

    assert_kind_of Plastic::Refused, outcome
    assert_empty retrieval.links("1")
  end

  def test_a_repeated_link_is_refused_with_one_row_left
    link("2")

    outcome, = link("2")

    assert_kind_of Plastic::Refused, outcome
    assert_equal 1, retrieval.links("1").size
  end
end
