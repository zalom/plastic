# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/harnesses/run_record"

# A run keeps the agent and harness it was claimed with, and takes the usage of its record when it ends.
class WorkNodeRunUsageTest < Plastic::TestCase
  Clock = Struct.new(:now)

  START = Time.utc(2026, 11, 17, 8, 0, 0)

  def setup
    super
    @clock = Clock.new(START)
    store_graphs.work.write_intent(title: "Alpha")
    store_graphs.work.activate_intent("1")
    work.add_node(intent_id: "1", title: "Build", criterion: "it works")
  end

  def work = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1", clock: @clock).work

  def run = retrieval.structure.runs("1").first

  def usage(**fields)
    base = { worker_session: "agent-a1", model: "claude-opus-5-5", input_tokens: 3, output_tokens: 4, cache_read_tokens: 5, cache_write_tokens: 6, cost_usd: 0.25, note: "" }
    Plastic::Harnesses::Usage.new(**base, **fields)
  end

  def claim = work.claim_node(intent_id: "1", id: "n1", by: "s-1", agent: "plastic-executor", harness: "claude-code")

  def finish_with(usage)
    claim
    @clock.now = START + 600
    work.done_node(intent_id: "1", id: "n1", by: "s-1", findings: "ok")
    work.record_run(intent_id: "1", id: "n1", by: "s-1", usage:)
  end

  def test_a_claim_opens_a_run_with_the_agent_and_the_harness
    claim

    assert_equal %w[plastic-executor claude-code], [run.agent, run.harness]
  end

  def test_the_usage_of_a_finished_run_is_stored_on_it
    finish_with(usage)

    assert_equal ["agent-a1", "claude-opus-5-5", 3, 4, 5, 6, 0.25, ""],
      run.to_h.values_at(:worker_session, :model, :input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens, :cost_usd, :usage_note)
  end

  def test_the_usage_note_of_a_record_that_was_not_found_is_stored
    finish_with(usage(model: nil, input_tokens: nil, output_tokens: nil, cache_read_tokens: nil, cache_write_tokens: nil, cost_usd: nil, note: "no Claude Code transcript for session s-1"))

    assert_equal [nil, "no Claude Code transcript for session s-1"], [run.model, run.usage_note]
  end

  def test_the_usage_goes_to_the_last_run_of_the_node_only
    claim
    work.release_node(intent_id: "1", id: "n1", by: "s-1")
    work.record_run(intent_id: "1", id: "n1", by: "s-1", usage: usage(model: "first"))
    @clock.now = START + 60
    claim
    work.fail_node(intent_id: "1", id: "n1", by: "s-1", reason: "x")
    work.record_run(intent_id: "1", id: "n1", by: "s-1", usage: usage(model: "second"))

    assert_equal %w[first second], retrieval.structure.runs("1").sort_by(&:number).map(&:model)
  end

  def test_the_run_window_comes_from_the_run_row_for_the_reader
    finish_with(usage)

    assert_equal [START, START + 600], [Time.parse(run.started_at), Time.parse(run.ended_at)]
  end
end
