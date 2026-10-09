# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkCompletionWriterFixture < Plastic::TestCase
  include LifecycleHelper

  def setup
    super
    @graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")
  end

  def writer = Plastic::Graph::Work::Completion::Writer.new(@graphs.databases, @graphs.retrieval, folder, session: "s-1")

  def ready(**options)
    @intent = accepted_intent(**options)
    review_off
  end
end

class WorkCompletionWriterTest < WorkCompletionWriterFixture
  def test_closing_an_accepted_intent_marks_it_delivered_with_the_verdict_judge
    ready
    writer.close("1")

    assert_equal %w[done delivered], retrieval.intent("1").to_h.values_at(:status, :disposition)
    assert_equal %w[verdict s-1], retrieval.completion("1").values_at("judge", "session_id")
  end

  def test_the_evidence_maps_each_criterion_key_to_its_nodes_and_findings
    ready
    writer.close("1")
    evidence = JSON.parse(retrieval.completion("1").fetch("evidence"))

    assert_equal [KEY], evidence.keys
    assert_includes evidence.fetch(KEY).to_s, "n1"
    assert_includes evidence.fetch(KEY).to_s, "Acceptance passes for works"
  end

  def test_closing_without_the_merge_and_map_records_raises_and_writes_nothing
    ready(records: "")

    error = assert_raises(Plastic::Invalid) { writer.close("1") }

    assert_includes error.message, "Merged:"
    assert_equal ["active", nil], [retrieval.intent("1").status, retrieval.completion("1")]
  end

  def test_closing_an_intent_with_problems_raises_them_and_writes_nothing
    open_intent

    error = assert_raises(Plastic::Invalid) { writer.close("1") }

    assert_match(/\AWrite the done criteria in spec.md/, error.message)
    assert_nil retrieval.completion("1")
  end

  def test_closing_releases_the_lock_of_the_closing_session
    ready
    @graphs.work.take_lock("1", session_id: "s-1", mode: "auto")
    writer.close("1")

    assert_nil retrieval.lock("1")
  end

  def test_closing_keeps_a_live_lock_another_session_holds
    ready
    @graphs.work.take_lock("1", session_id: "s-2", mode: "auto")
    writer.close("1")

    assert_equal "s-2", retrieval.lock("1").session_id
  end

  def test_abandoning_a_done_intent_changes_nothing
    ready
    writer.close("1")
    writer.abandon("1")

    assert_equal %w[done delivered], retrieval.intent("1").to_h.values_at(:status, :disposition)
  end

  def test_the_file_evidence_reader_is_gone
    refute_respond_to writer, :evidence
    refute_respond_to @graphs.work, :completion_evidence
  end
end

class WorkCompletionAbandonTest < WorkCompletionWriterFixture
  def setup
    super
    @intent = open_intent
  end

  def dropped(intent = @intent)
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDropped: the need went away.\n")
    sync_up
  end

  def test_abandoning_marks_the_intent_abandoned_and_writes_no_completion
    dropped
    writer.abandon("1")

    assert_equal %w[abandoned cancelled], retrieval.intent("1").to_h.values_at(:status, :disposition)
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
end
