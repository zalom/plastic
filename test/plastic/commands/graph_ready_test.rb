# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/graph_ready"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/edge_add"

class GraphReadyTest < Plastic::TestCase
  def call(*args) = plastic("graph", "ready", *args, table: Plastic::CLI::TABLE)

  def add_node(title) = plastic("node", "add", "1", title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def test_an_open_node_with_no_need_is_ready
    open_intent
    add_node("a")

    result = call("1")

    assert_equal 0, result.code
    assert_includes result.out, "ready: n1 a"
  end

  def test_a_node_whose_need_is_not_done_is_not_ready
    open_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)

    result = call("1")

    assert_includes result.out, "ready: n1 a"
    refute_includes result.out, "ready: n2 b"
  end

  def test_claimed_work_stays_with_its_worker
    open_intent
    add_node("a")
    add_node("b")
    plastic("edge", "add", "1", "n1", "n2", table: Plastic::CLI::TABLE)
    plastic("node", "claim", "1", "n1", table: Plastic::CLI::TABLE)
    plastic("node", "done", "1", "n1", "--judge", "owner", "--findings", "ok", table: Plastic::CLI::TABLE)
    plastic("node", "claim", "1", "n2", table: Plastic::CLI::TABLE)

    result = call("1")

    refute_includes result.out, "ready:"
    assert_includes result.out, "Continue node n2 with its worker"
  end
end
