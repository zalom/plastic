# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../test_helpers/harness_record_fixtures"
require_relative "../../../lib/plastic/harnesses/run_record"

# Which subagent Plastic credits with a node run when more than one subagent ran a claim of the same ids.
class HarnessesRunRecordClaimTest < Plastic::TestCase
  include Plastic::TestHelpers::HarnessRecordFixtures

  def read(from, to) = Plastic::Harnesses::RunRecord.new(home: @home).read(harness: "claude-code", session: "s-1", from:, to:, claim: "1 n1")

  def claim(agent, at, command = "plastic node claim 1 n1")
    write_claude("agent-#{agent}", jsonl(claude_claim_call(at, command)), under: ["s-1", "subagents"])
  end

  def test_the_later_claim_of_one_node_by_a_second_subagent_credits_the_second_run
    write_claude("s-1", jsonl(claude_turn("2026-11-23T17:00:00Z", id: "p1")))
    claim("a1", "2026-11-23T17:10:00Z")
    claim("b2", "2026-11-23T17:20:00Z")

    assert_equal "agent-b2", read(Time.utc(2026, 11, 23, 17, 20, 2), Time.utc(2026, 11, 23, 17, 30)).worker_session
  end

  def test_a_claim_turn_stamped_inside_the_second_the_run_started_credits_that_subagent
    write_claude("s-1", jsonl(claude_turn("2026-11-23T18:00:00Z", id: "p1")))
    claim("a1", "2026-11-23T18:35:26.218Z")
    claim("b2", "2026-11-23T19:17:43.615Z")

    assert_equal "agent-b2", read(Time.utc(2026, 11, 23, 19, 17, 43), Time.utc(2026, 11, 23, 19, 17, 52)).worker_session
  end
end
