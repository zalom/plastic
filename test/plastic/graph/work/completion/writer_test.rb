# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkCompletionWriterTest < Plastic::TestCase
  EVIDENCE = { "It works" => "the tests pass" }.freeze

  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
    @intent = open_intent
  end

  def writer = Plastic::Graph::Work::Completion::Writer.new(@graphs.databases, @graphs.retrieval, folder, session: "s-1")

  def ready
    write("#{@intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- It works\n")
    write("#{@intent.dir}/outcome.md", "# Outcome\n\nDelivered.\n")
    sync_up
    work = @graphs.work
    work.add_node(intent_id: "1", title: "Build")
    work.claim_node(intent_id: "1", id: "n1", by: "a")
    work.done_node(intent_id: "1", id: "n1", judge: "tests", findings: "green")
  end

  def test_closing_a_ready_intent_marks_it_delivered_and_keeps_the_attestation
    ready
    writer.close("1", judge: "agent", evidence: EVIDENCE)

    assert_equal %w[done delivered], retrieval.intent("1").to_h.values_at(:status, :disposition)
    assert_equal %w[agent s-1], retrieval.completion("1").values_at("judge", "session_id")
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
