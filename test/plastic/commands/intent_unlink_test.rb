# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_link"
require_relative "../../../scripts/lib/plastic/commands/intent_unlink"

class IntentUnlinkTest < Plastic::TestCase
  def link(*args) = plastic("intent", "link", *args, table: Plastic::CLI::TABLE)

  def call(*args) = plastic("intent", "unlink", *args, table: Plastic::CLI::TABLE)

  def test_unlink_removes_the_row_and_leaves_another_kind_in_place
    open_intent
    open_intent("Beta")
    link("1", "cites", "2")
    link("1", "chain", "2")

    result = call("1", "cites", "2")

    assert_equal 0, result.code
    links = store_graphs.retrieval.links("1")

    assert_equal 1, links.size
    assert_equal "chain", links.first.kind
  end

  def test_unlinking_a_missing_link_fails
    open_intent
    open_intent("Beta")

    result = call("1", "cites", "2")

    assert_equal 1, result.code
  end

  def test_a_failed_unlink_succeeds_once_the_link_exists
    open_intent
    open_intent("Beta")
    call("1", "cites", "2")
    link("1", "cites", "2")

    result = call("1", "cites", "2")

    assert_equal 0, result.code
    assert_empty store_graphs.retrieval.links("1")
  end
end
