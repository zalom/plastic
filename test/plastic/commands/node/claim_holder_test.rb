# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/claim"
require_relative "../../../../lib/plastic/commands/node/renew"
require_relative "../../../../lib/plastic/commands/node/done"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/graph/show"

# A node claim belongs to one session and lapses after 15 minutes without a command of its holder.
class NodeClaimHolderTest < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 17, 8, 0, 0)

  def setup
    super
    @clock = Clock.new(START)
    alpha_with_node
  end

  def at(minutes) = @clock.now = START + (minutes * 60)

  def as(session, *argv) = plastic(*argv, env: { "CLAUDE_CODE_SESSION_ID" => session }, table: Plastic::CLI::TABLE, clock: @clock)

  def node = store_graphs.retrieval.node("1", "n1")

  def test_a_claim_renewed_14_minutes_ago_is_refused_with_exit_3_naming_the_holder
    as("s-1", "node", "claim", "1", "n1")
    at(14)

    result = as("s-2", "node", "claim", "1", "n1")

    assert_equal [3, "s-1"], [result.code, node.claimed_by]
    assert_includes result.err, "s-1"
  end

  def test_a_claim_renewed_16_minutes_ago_is_taken_by_another_session
    as("s-1", "node", "claim", "1", "n1")
    at(16)

    result = as("s-2", "node", "claim", "1", "n1")

    assert_equal [0, "s-2"], [result.code, node.claimed_by]
    assert_equal %w[lapsed], store_graphs.retrieval.structure.runs("1").first(1).map(&:result)
  end

  def test_the_old_holder_of_a_taken_claim_exits_3_naming_the_new_holder_and_changes_nothing
    as("s-1", "node", "claim", "1", "n1")
    at(16)
    as("s-2", "node", "claim", "1", "n1")

    result = as("s-1", "node", "done", "1", "n1", "late")

    assert_equal 3, result.code
    assert_includes result.err, "s-2"
    assert_equal ["claimed", "s-2", nil], [node.state, node.claimed_by, node.findings]
  end

  def test_a_lapsed_claim_nobody_took_completes_for_its_holder
    as("s-1", "node", "claim", "1", "n1")
    at(40)

    assert_equal 0, as("s-1", "node", "done", "1", "n1", "checked").code
    assert_equal "done", node.state
  end

  def test_any_command_of_the_holder_renews_its_claim
    as("s-1", "node", "claim", "1", "n1")
    at(10)
    as("s-1", "graph", "show", "1")
    at(20)

    assert_equal 3, as("s-2", "node", "claim", "1", "n1").code
  end

  def test_a_command_of_another_session_does_not_renew
    as("s-1", "node", "claim", "1", "n1")
    at(10)
    as("s-2", "graph", "show", "1")
    at(16)

    assert_equal 0, as("s-2", "node", "claim", "1", "n1").code
  end

  def test_node_renew_keeps_the_claim_alive
    as("s-1", "node", "claim", "1", "n1")
    at(10)

    assert_equal 0, as("s-1", "node", "renew", "1", "n1").code
    assert_equal "2026-11-17T08:10:00Z", node.seen_at
  end

  def test_node_renew_of_a_node_held_by_another_session_exits_3
    as("s-1", "node", "claim", "1", "n1")

    result = as("s-2", "node", "renew", "1", "n1")

    assert_equal [3, "2026-11-17T08:00:00Z"], [result.code, node.seen_at]
  end

  def test_graph_show_names_the_holder_of_a_claimed_node
    as("s-1", "node", "claim", "1", "n1")

    assert_includes as("s-2", "graph", "show", "1").out, "node: n1 claimed Build, held by s-1"
  end
end
