# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/graph/ready"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/node/claim"
require_relative "../../../../lib/plastic/commands/node/done"

# `graph ready` reports each claimed node whose claim has run longer than the node's deadline. It moves no node.
class GraphReadyOverdueTest < Plastic::TestCase
  CLAIMED = Time.utc(2026, 11, 23, 9, 0, 0)
  Clock = Struct.new(:now)
  SESSION = { "PLASTIC_SESSION" => "s-1" }.freeze

  def run_at(minutes, *argv) = plastic(*argv, env: SESSION, table: Plastic::CLI::TABLE, clock: Clock.new(CLAIMED + (minutes * 60)))

  def ready(minutes, *flags) = run_at(minutes, "graph", "ready", "1", *flags)

  def overdue_json(minutes) = JSON.parse(ready(minutes, "--json").out).dig("result", "overdue")

  def claimed_build(*deadline)
    open_keyed_intent
    run_at(0, "node", "add", "1", "Build", "--criterion", "done", *deadline)
    run_at(0, "node", "claim", "1", "n1", "--agent", "tester")
  end

  def test_a_claim_older_than_its_deadline_is_reported_as_overdue
    claimed_build("--deadline", "30")

    result = ready(42)

    assert_call result, code: 0, err: "", out: ["overdue: n1 Build claimed 42 minutes ago, deadline 30"]
  end

  def test_a_claim_younger_than_its_deadline_is_not_reported
    claimed_build("--deadline", "30")

    refute_includes ready(20).out, "overdue:"
  end

  def test_a_claim_exactly_at_its_deadline_is_not_yet_overdue
    claimed_build("--deadline", "30")

    refute_includes ready(30).out, "overdue:"
  end

  def test_a_node_with_no_deadline_is_never_overdue
    claimed_build

    refute_includes ready(600).out, "overdue:"
  end

  def test_a_done_node_past_its_deadline_is_not_overdue
    claimed_build("--deadline", "30")
    run_at(10, "node", "done", "1", "n1", "ok")

    refute_includes ready(42).out, "overdue:"
  end

  def test_the_json_answer_carries_each_overdue_node_with_its_holder_and_minutes
    claimed_build("--deadline", "30")

    assert_equal [{ "id" => "n1", "title" => "Build", "claimed_by" => "s-1", "claimed_minutes" => 42, "deadline" => 30 }], overdue_json(42)
  end

  def test_the_json_answer_carries_an_empty_list_when_no_node_is_overdue
    claimed_build("--deadline", "30")

    assert_empty overdue_json(20)
  end

  def test_an_overdue_node_stays_claimed_by_its_session
    claimed_build("--deadline", "30")
    ready(42)

    node = store_graphs.retrieval.node("1", "n1")

    assert_equal %w[claimed s-1], [node.state, node.claimed_by]
  end
end
