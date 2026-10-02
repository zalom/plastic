# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/node_add"

class NodeAddTest < Plastic::TestCase
  def call(*args) = plastic("node", "add", *args, table: Plastic::CLI::TABLE)

  def test_missing_criterion_exits_2
    open_intent

    result = call("1", "do the thing")

    assert_equal 2, result.code
  end

  def test_two_nodes_read_n1_and_n2
    open_intent

    first = call("1", "do the thing", "--criterion", "it is done")
    second = call("1", "do another thing", "--criterion", "it is done too")

    assert_includes first.out, "node: n1"
    assert_includes second.out, "node: n2"
  end

  def test_refused_on_a_done_intent
    open_intent
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :intent_id", intent_id: "1")
    end

    result = call("1", "do the thing", "--criterion", "it is done")

    assert_equal 3, result.code
  end

  def test_refused_on_a_missing_intent
    result = call("9", "do the thing", "--criterion", "it is done")

    assert_equal 3, result.code
    assert_includes result.err, "no intent 9"
  end

  def test_takes_the_intent_as_its_subject
    assert_equal [:intent_id], Plastic::Commands::NodeAdd.describe.subject
  end
end
