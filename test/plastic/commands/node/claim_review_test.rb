# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/claim"
require_relative "../../../../lib/plastic/commands/node/renew"
require_relative "../../../../lib/plastic/commands/node/done"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/status"

# The rules of a claim that the first review of batch 3 found missing: who may finish a node, which agent runs it,
# when a claim without a time lapses, which commands renew, and what a renewal prints.
class NodeClaimReviewTest < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 17, 8, 0, 0)

  def setup
    super
    @clock = Clock.new(START)
    alpha_with_node
  end

  def at(minutes) = @clock.now = START + (minutes * 60)

  def as(session, *argv, env: {}) = plastic(*argv, env: { "CLAUDE_CODE_SESSION_ID" => session }.merge(env), table: Plastic::CLI::TABLE, clock: @clock)

  def node = store_graphs.retrieval.node("1", "n1")

  def snapshot = [node.to_h, store_graphs.retrieval.structure.runs("1").map(&:to_h)]

  def reclaim_lapsed_then_finish
    as("s-1", "node", "claim", "1", "n1")
    at(16)
    as("s-2", "node", "claim", "1", "n1")
    as("s-2", "node", "done", "1", "n1", "new holder")
  end

  def test_the_old_holder_cannot_finish_a_node_the_new_holder_finished
    reclaim_lapsed_then_finish

    result = as("s-1", "node", "done", "1", "n1", "old holder")

    assert_equal [3, "new holder"], [result.code, node.findings]
    assert_includes result.err, "s-2"
  end

  def test_the_same_holder_finishing_twice_exits_0_and_changes_nothing
    as("s-1", "node", "claim", "1", "n1")
    as("s-1", "node", "done", "1", "n1", "first")
    before = snapshot
    at(5)

    result = as("s-1", "node", "done", "1", "n1", "second")

    assert_equal [0, before], [result.code, snapshot]
  end

  def test_a_claim_with_an_agent_records_it_on_the_run
    as("s-1", "node", "claim", "1", "n1", "--agent", "plastic-executor")

    assert_equal ["plastic-executor"], store_graphs.retrieval.structure.runs("1").map(&:agent)
  end

  def test_a_claim_without_an_agent_records_an_empty_one
    as("s-1", "node", "claim", "1", "n1")

    assert_equal [""], store_graphs.retrieval.structure.runs("1").map(&:agent)
  end

  def test_a_claimed_node_with_no_time_and_no_holder_is_taken
    store_graphs.databases.fetch(:store).transaction do |batch|
      batch.add("UPDATE nodes SET state = 'claimed', claimed_by = NULL, claimed_at = NULL, seen_at = NULL WHERE id = 'n1'")
    end

    assert_equal [0, "s-2"], [as("s-2", "node", "claim", "1", "n1").code, node.claimed_by]
  end

  def test_a_claimed_node_with_an_empty_time_lapses
    node = Plastic::Graph::Work::Node.from_h({ id: "n1", state: "claimed", claimed_by: "s-1", claimed_at: "", seen_at: "" })

    assert node.lapsed?(START)
  end

  def test_status_by_the_holder_renews_its_claim
    as("s-1", "node", "claim", "1", "n1")
    at(10)

    as("s-1", "status")

    assert_equal "2026-11-17T08:10:00Z", node.seen_at
  end

  def test_the_printed_graph_file_holds_no_renewal_time
    as("s-1", "node", "claim", "1", "n1")

    refute_includes File.read(File.join(store_root, "store/1--alpha/graph.json")), "seen_at"
  end

  def test_a_renewal_prints_no_file_and_leaves_the_graph_file_alone
    as("s-1", "node", "claim", "1", "n1")
    path = File.join(store_root, "store/1--alpha/graph.json")
    before = File.read(path)
    at(10)

    result = as("s-1", "node", "renew", "1", "n1")

    assert_equal [0, before, "node: n1 renewed\n"], [result.code, File.read(path), result.out.lines.first]
    refute_includes result.out, "files:"
  end

  def test_a_graph_file_import_keeps_the_renewal_time_of_the_row
    as("s-1", "node", "claim", "1", "n1")
    at(10)
    as("s-1", "node", "renew", "1", "n1")
    File.write(File.join(store_root, "store/1--alpha/graph.json"), File.read(File.join(store_root, "store/1--alpha/graph.json")).sub('"findings": null', '"findings": "edited"'))

    as("s-1", "sync", "up")

    assert_equal "2026-11-17T08:10:00Z", node.seen_at
  end

  def test_a_terminal_with_no_session_variable_claims_as_the_terminal_login
    result = plastic("node", "claim", "1", "n1", env: { "USER" => "ada" }, table: Plastic::CLI::TABLE, clock: @clock)

    assert_equal [0, ["terminal-ada"]], [result.code, store_graphs.retrieval.structure.runs("1").map(&:session_id)]
  end
end
