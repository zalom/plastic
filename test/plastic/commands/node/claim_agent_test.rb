# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/node/claim"
require_relative "../../../../lib/plastic/commands/node/add"
require_relative "../../../../lib/plastic/commands/node/done"

# A claim names the agent that runs the node, and the run keeps the agent, the harness and the session.
class NodeClaimAgentTest < Plastic::TestCase
  def setup
    super
    alpha_with_node
  end

  def claim(*args, env: { "PLASTIC_SESSION" => "s-1" }) = plastic("node", "claim", "1", "n1", *args, env:, table: Plastic::CLI::TABLE)

  def runs = structure.runs("1")

  def test_a_claim_without_the_agent_exits_2_and_names_the_flag
    result = claim

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "--agent"
  end

  def test_a_claim_without_the_agent_writes_no_claim
    claim

    assert_equal ["open", []], [retrieval.node("1", "n1").state, runs]
  end

  def test_a_claim_with_an_empty_agent_exits_2
    assert_equal 2, claim("--agent", "").code
  end

  def test_a_claim_with_the_agent_records_it_on_the_run
    result = claim("--agent", "plastic-executor")

    assert_equal [0, "plastic-executor"], [result.code, runs.first.agent]
  end

  def test_a_claim_in_a_claude_code_session_records_the_harness_and_the_session
    claim("--agent", "a", env: { "CLAUDE_CODE_SESSION_ID" => "c-9" })

    assert_equal ["claude-code", "c-9"], [runs.first.harness, runs.first.session_id]
  end

  def test_a_claim_in_a_codex_session_records_the_harness
    claim("--agent", "a", env: { "CODEX_THREAD_ID" => "x-9" })

    assert_equal "codex", runs.first.harness
  end

  def test_a_claim_with_only_a_plastic_session_records_an_empty_harness
    claim("--agent", "a")

    assert_equal "", runs.first.harness
  end

  def test_the_next_line_after_a_release_offers_a_claim_that_names_the_agent
    claim("--agent", "a")
    result = plastic("node", "release", "1", "n1", env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

    assert_includes result.out, "next: plastic node claim 1 n1 --agent NAME"
  end

  def test_a_done_with_no_harness_record_keeps_the_run_and_says_what_was_not_found
    claim("--agent", "a", env: { "CLAUDE_CODE_SESSION_ID" => "c-9" })
    result = plastic("node", "done", "1", "n1", "ok", env: { "CLAUDE_CODE_SESSION_ID" => "c-9" }, table: Plastic::CLI::TABLE)
    run = runs.first

    assert_equal [0, "done", true], [result.code, run.result, run.usage_note.include?("no Claude Code transcript for session c-9")]
  end

  def test_a_run_shows_in_graph_show_with_its_agent_and_its_note
    claim("--agent", "a", env: { "CLAUDE_CODE_SESSION_ID" => "c-9" })
    plastic("node", "done", "1", "n1", "ok", env: { "CLAUDE_CODE_SESSION_ID" => "c-9" }, table: Plastic::CLI::TABLE)
    line = plastic("graph", "show", "1", table: Plastic::CLI::TABLE).out.lines.grep(/^run: /).first

    assert_match(/\Arun: n1 #1 agent a, claude-code session c-9, done; no Claude Code transcript for session c-9/, line)
  end
end
