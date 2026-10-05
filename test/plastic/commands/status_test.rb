# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/status"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_claim"

class StatusTest < Plastic::TestCase
  def call(*args) = plastic("status", *args, table: Plastic::CLI::TABLE)

  def test_a_second_store_is_not_missed
    open_intent
    Plastic::Graph.open(home: @plastic_home, store: "other").work.write_intent(title: "Beta")

    result = call

    assert_equal 0, result.code
    assert_includes result.out, "other"
    assert_includes result.out, "Beta"
  end

  def test_status_offers_plastic_next_as_the_next_command
    open_intent

    result = call

    assert_includes result.out, "next: plastic next"
  end

  def test_an_intent_without_nodes_says_so
    open_intent

    assert_includes call.out, "no nodes"
  end

  def test_counts_the_nodes_of_an_intent_by_state
    open_intent
    2.times { |i| plastic("node", "add", "1", "node #{i}", "--criterion", "done", table: Plastic::CLI::TABLE) }
    plastic("node", "claim", "1", "n1", table: Plastic::CLI::TABLE)

    assert_includes call.out, "claimed: 1, open: 1"
    assert_equal 0, call.code
    assert_equal "", call.err
  end
end
