# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_claim"
require_relative "../../../scripts/lib/plastic/commands/node_release"
require_relative "../../../scripts/lib/plastic/commands/node_fail"
require_relative "../../../scripts/lib/plastic/commands/node_park"
require_relative "../../../scripts/lib/plastic/commands/node_answer"
require_relative "../../../scripts/lib/plastic/commands/node_done"

class NodeMovesTest < Plastic::TestCase
  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def test_releasing_an_open_node_is_refused
    open_intent
    add_node("a")

    result = plastic("node", "release", "1", "n1", table: Plastic::CLI::TABLE)

    assert_equal 3, result.code
  end

  def test_a_bad_judge_exits_2
    open_intent
    add_node("a")
    plastic("node", "claim", "1", "n1", table: Plastic::CLI::TABLE)

    result = plastic("node", "done", "1", "n1", "--judge", "vibes", "--findings", "ok", table: Plastic::CLI::TABLE)

    assert_equal 2, result.code
  end

  def test_failing_an_open_node_is_refused
    open_intent
    add_node("a")

    result = plastic("node", "fail", "1", "n1", "--reason", "boom", table: Plastic::CLI::TABLE)

    assert_equal 3, result.code
  end

  def test_parking_an_open_node_is_refused
    open_intent
    add_node("a")

    result = plastic("node", "park", "1", "n1", "--question", "which way?", table: Plastic::CLI::TABLE)

    assert_equal 3, result.code
  end

  def test_answering_an_open_node_is_refused
    open_intent
    add_node("a")

    result = plastic("node", "answer", "1", "n1", "--answer", "go left", table: Plastic::CLI::TABLE)

    assert_equal 3, result.code
  end
end
