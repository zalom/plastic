# frozen_string_literal: true

require_relative "../../../test_helper"

# A write stores its owning rows and one pending row in one transaction; a drain turns each pending row into one work_log line.
class WorkLogTest < Plastic::TestCase
  fixtures :empty

  class Died < StandardError; end

  class DiesAfterCommit < Plastic::Graph::Work::Log
    def drain(intent_id)
      @calls = @calls.to_i + 1
      (@calls == 2) ? raise(Died, "the process died after the owning commit") : super
    end
  end

  def graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def work(session = "s-1") = graphs(session).work

  def dying(session)
    open = graphs(session)
    log = DiesAfterCommit.new(open.databases, open.retrieval, session:)
    Plastic::Graph::WorkGraph.new(open.databases, folder:, retrieval: open.retrieval, session:, log:)
  end

  def lines = graphs.retrieval.work_log("1")

  def open_intent(title = "Alpha") = work.write_intent(title:)

  def pending = graphs.databases.fetch(:store).rows("SELECT * FROM work_log_pending ORDER BY rowid")

  def rulings = graphs.databases.fetch(:store).rows("SELECT id FROM rulings WHERE intent_id = '1'")

  def die_after_commit(text = "kept", session: "s-dead") = assert_raises(Died) { dying(session).add_ruling(intent_id: "1", text:) }

  def test_a_process_that_dies_after_the_owning_commit_leaves_the_owning_row_and_one_pending_row
    open_intent
    die_after_commit

    assert_equal [1, 1, %w[opened]], [rulings.size, pending.size, lines.map(&:kind)]
    assert_equal ["s-dead", "ruled"], pending.first.values_at("session_id", "kind")
  end

  def test_the_next_write_to_the_intent_drains_the_pending_row_into_one_line_with_the_writers_session
    open_intent
    die_after_commit
    work("s-2").add_ruling(intent_id: "1", text: "after")

    assert_equal [%w[opened s-1], %w[ruled s-dead], %w[ruled s-2]], lines.map { |line| line.values_at(:kind, :session_id) }
    assert_empty pending
  end

  def test_two_drains_add_one_line
    open_intent
    die_after_commit

    assert_equal [1, 0], [work.drain_log("1"), work.drain_log("1")]
    assert_equal %w[opened ruled], lines.map(&:kind)
  end

  def test_draining_every_intent_names_each_one_and_how_many_lines_it_gained
    open_intent
    open_intent("Beta")
    die_after_commit
    assert_raises(Died) { dying("s-dead").add_ruling(intent_id: "2", text: "other") }

    assert_equal({ "1" => 1, "2" => 1 }, work.drain_logs)
    assert_empty work.drain_logs
  end

  def test_two_handles_that_write_one_intent_keep_both_lines_at_distinct_positions
    open_intent
    die_after_commit("a", session: "s-a")
    die_after_commit("b", session: "s-b")
    first = graphs("s-a").work
    second = graphs("s-b").work
    first.drain_log("1")
    second.drain_log("1")

    assert_equal [1, 2, 3], lines.map(&:position)
    assert_equal %w[s-1 s-a s-b], lines.map(&:session_id)
  end

  def replay(row)
    columns = %i[write_id intent_id at session_id kind text origin_id]
    sql = "INSERT INTO work_log_pending(write_id, intent_id, at, phase, node, session_id, kind, path, sha256, text, origin_id) " \
          "VALUES (:write_id, :intent_id, :at, '', '', :session_id, :kind, '', '', :text, :origin_id)"
    graphs.databases.fetch(:store).transaction { |batch| batch.add(sql, **row.transform_keys(&:to_sym).slice(*columns)) }
  end

  def test_a_drained_line_keeps_its_own_write_id_and_a_replayed_write_id_adds_nothing
    open_intent
    die_after_commit
    row = pending.first
    work.drain_log("1")
    replay(row)
    work.drain_log("1")

    assert_equal [%w[opened ruled], []], [lines.map(&:kind), pending]
  end

  def test_an_intent_with_no_pending_row_gains_no_line_from_a_drain
    open_intent

    assert_equal [0, 1], [work.drain_log("1"), lines.size]
  end
end
