# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/node_add"

class NodeAddTest < Plastic::TestCase
  include LifecycleHelper

  def call(*args) = plastic("node", "add", *args, table: Plastic::CLI::TABLE)

  def nodes = work_rows("nodes")

  def test_missing_criterion_exits_2
    specified

    assert_equal 2, call("1", "do the thing").code
  end

  def test_a_known_key_writes_the_node_with_the_key
    specified

    result = call("1", "do the thing", "--criterion", KEY)

    assert_includes result.out, "node: n1"
    assert_equal [KEY], nodes.map { |row| row.fetch("criterion") }
  end

  def test_two_nodes_read_n1_and_n2
    specified

    call("1", "first", "--criterion", KEY)

    assert_includes call("1", "second", "--criterion", KEY).out, "node: n2"
  end

  def test_an_unknown_key_exits_1_naming_the_keys_the_spec_has_and_writes_no_node
    specified({ KEY => CRITERION, "other" => "Another" })

    result = call("1", "do the thing", "--criterion", "nope")

    assert_equal [1, true], [result.code, %w[works other].all? { |key| result.err.include?(key) }]
    assert_empty nodes
  end

  def test_the_criterion_text_is_not_a_key
    specified

    assert_equal [1, []], [call("1", "do the thing", "--criterion", CRITERION).code, nodes]
  end

  def test_no_synced_spec_exits_1_saying_to_write_the_done_criteria_and_sync_up
    open_intent

    result = call("1", "do the thing", "--criterion", KEY)

    assert_equal [1, true], [result.code, result.err.include?("done criteria") && result.err.include?("sync up")]
    assert_empty nodes
  end

  def test_refused_on_a_done_intent
    open_intent(status: "done")

    assert_equal 1, call("1", "do the thing", "--criterion", KEY).code
  end

  def test_refused_on_a_missing_intent
    result = call("9", "do the thing", "--criterion", KEY)

    assert_equal 1, result.code
    assert_includes result.err, "no intent 9"
  end

  def test_takes_the_intent_as_its_subject
    assert_equal [:intent_id], Plastic::Commands::NodeAdd.describe.subject
  end
end
