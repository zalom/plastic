# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkCompletionWriterFixture < Plastic::TestCase
  EVIDENCE = { "It works" => "the tests pass" }.freeze
  VERIFIED = "# Outcome\n\nDelivered.\n\n## Verification\n- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n"

  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    @intent = open_intent
  end

  def writer = Plastic::Graph::Work::Completion::Writer.new(@graphs.databases, @graphs.retrieval, folder, session: "s-1")

  def ready(outcome: VERIFIED)
    write("#{@intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- It works\n")
    write("#{@intent.dir}/outcome.md", outcome)
    sync_up
    work = @graphs.work
    work.add_node(intent_id: "1", title: "Build")
    work.claim_node(intent_id: "1", id: "n1", by: "a")
    work.done_node(intent_id: "1", id: "n1", judge: "tests", findings: "green")
  end
end

class WorkCompletionWriterTest < WorkCompletionWriterFixture
  def test_closing_a_ready_intent_marks_it_delivered_and_keeps_the_attestation
    ready
    writer.close("1", judge: "agent", evidence: EVIDENCE)

    assert_equal %w[done delivered], retrieval.intent("1").to_h.values_at(:status, :disposition)
    assert_equal %w[agent s-1], retrieval.completion("1").values_at("judge", "session_id")
  end

  def test_closing_without_the_merge_and_map_records_raises_and_writes_nothing
    ready(outcome: "# Outcome\n\nDelivered.\n")

    error = assert_raises(Plastic::Invalid) { writer.close("1", judge: "agent", evidence: EVIDENCE) }

    assert_includes error.message, "Merged:"
    assert_equal ["open", nil], [retrieval.intent("1").status, retrieval.completion("1")]
  end

  def test_evidence_validates_against_the_criterion_keys
    write("#{@intent.dir}/completion.json", JSON.generate({ "works" => "ok" }))

    assert_equal({ "works" => "ok" }, writer.evidence("1", "completion.json", ["works"]))
    assert_raises(Plastic::Invalid) { writer.evidence("1", "completion.json", ["other"]) }
  end

  def test_closing_an_intent_with_problems_raises_them_and_writes_nothing
    error = assert_raises(Plastic::Invalid) { writer.close("1", judge: "agent", evidence: EVIDENCE) }

    assert_match(/\AWrite the done criteria in spec.md/, error.message)
    assert_nil retrieval.completion("1")
  end

  def test_closing_with_evidence_for_the_wrong_criteria_is_refused
    ready

    assert_raises(Plastic::Invalid) { writer.close("1", judge: "agent", evidence: { "Other" => "text" }) }
    assert_equal "open", retrieval.intent("1").status
  end

  def test_closing_releases_the_lock_of_the_closing_session
    ready
    @graphs.work.take_lock("1", session_id: "s-1", mode: "auto")
    writer.close("1", judge: "agent", evidence: EVIDENCE)

    assert_nil retrieval.lock("1")
  end

  def test_closing_keeps_a_live_lock_another_session_holds
    ready
    @graphs.work.take_lock("1", session_id: "s-2", mode: "auto")
    writer.close("1", judge: "agent", evidence: EVIDENCE)

    assert_equal "s-2", retrieval.lock("1").session_id
  end

  def test_evidence_reads_the_file_named_inside_the_intent
    write("#{@intent.dir}/completion.json", JSON.generate(EVIDENCE))

    assert_equal EVIDENCE, writer.evidence("1", "completion.json", ["It works"])
  end
end

class WorkCompletionAbandonTest < WorkCompletionWriterFixture
  def dropped(intent = @intent)
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDropped: the need went away.\n")
    sync_up
  end

  def test_abandoning_marks_the_intent_abandoned_and_writes_no_completion
    dropped
    writer.abandon("1")

    assert_equal %w[abandoned abandoned], retrieval.intent("1").to_h.values_at(:status, :disposition)
    assert_nil retrieval.completion("1")
  end

  def test_abandoning_stamps_the_close_time
    dropped
    writer.abandon("1")

    refute_nil retrieval.intent("1").to_h[:closed_at]
  end

  def test_abandoning_a_future_intent_closes_it
    dropped(open_intent("Later", status: "future"))
    writer.abandon("2")

    assert_equal "abandoned", retrieval.intent("2").status
  end

  def test_abandoning_releases_the_lock_of_the_closing_session
    dropped
    @graphs.work.take_lock("1", session_id: "s-1", mode: "auto")
    writer.abandon("1")

    assert_nil retrieval.lock("1")
  end

  def test_abandoning_keeps_a_live_lock_another_session_holds
    dropped
    @graphs.work.take_lock("1", session_id: "s-2", mode: "auto")
    writer.abandon("1")

    assert_equal "s-2", retrieval.lock("1").session_id
  end

  def test_abandoning_without_an_outcome_raises_and_writes_nothing
    assert_raises(Plastic::Invalid) { writer.abandon("1") }
    assert_equal "open", retrieval.intent("1").status
  end

  def test_abandoning_a_done_intent_changes_nothing
    ready
    writer.close("1", judge: "agent", evidence: EVIDENCE)
    writer.abandon("1")

    assert_equal %w[done delivered], retrieval.intent("1").to_h.values_at(:status, :disposition)
  end
end
