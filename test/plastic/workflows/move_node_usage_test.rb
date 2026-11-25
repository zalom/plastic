# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../test_helpers/harness_record_fixtures"
require_relative "../../../lib/plastic/commands/node/claim"
require_relative "../../../lib/plastic/commands/node/add"
require_relative "../../../lib/plastic/commands/node/done"

# The done command keeps on the run the usage of the worker's turns, up to the end of the second the run ended in.
class MoveNodeUsageTest < Plastic::TestCase
  include Plastic::TestHelpers::HarnessRecordFixtures

  Clock = Struct.new(:now)

  def setup
    super
    @clock = Clock.new(Time.utc(2026, 11, 23, 19, 51, 27.5r))
    alpha_with_node
  end

  def as_worker(*argv) = plastic(*argv, env: { "CLAUDE_CODE_SESSION_ID" => "s-1" }, table: Plastic::CLI::TABLE, clock: @clock)

  # The worker claims at 19:51:27.299, inside the run's stored start, and its last turn is stamped at 19:51:31.162.
  def write_transcripts
    write_claude("s-1", jsonl(claude_turn("2026-11-23T19:00:00Z", id: "p1")))
    write_claude("agent-w1", jsonl(claude_claim_call("2026-11-23T19:51:27.299Z", "plastic node claim 1 n1 --agent w1"),
      claude_turn("2026-11-23T19:51:31.162Z", id: "m2", output: 402)), under: ["s-1", "subagents"])
  end

  def test_the_worker_turn_stamped_inside_the_second_the_run_ended_is_counted
    as_worker("node", "claim", "1", "n1", "--agent", "w1")
    @clock.now = Time.utc(2026, 11, 23, 19, 51, 31.5r)
    write_transcripts
    as_worker("node", "done", "1", "n1", "ok")

    assert_equal ["agent-w1", 412], structure.runs("1").first.then { |run| [run.worker_session, run.output_tokens] }
  end
end
