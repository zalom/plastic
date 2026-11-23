# frozen_string_literal: true

require "digest"
require_relative "../../../test_helper"

# Every intent write stores its owning rows and its one work_log line.
class WorkLoggedWritesTest < Plastic::TestCase
  fixtures :empty

  def graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def work = graphs.work

  def lines(id = "1") = graphs.retrieval.structure.work_log(id)

  def kinds(id = "1") = lines(id).map(&:kind)

  def intent(title = "Alpha") = work.write_intent(title:)

  def forget(id = "1") = graphs.databases.fetch(:store).transaction { |batch| batch.remove(:work_log, intent_id: id) }

  def test_a_new_intent_stores_its_rows_first_and_one_opened_line_second
    intent

    assert_equal [["opened", "s-1", "Opened: Alpha"]], lines.map { |line| line.values_at(:kind, :session_id, :text) }
  end

  def test_a_ruling_appends_one_line
    intent
    work.add_ruling(intent_id: "1", text: "Flowbite styles every delivery")

    assert_equal %w[opened ruled], kinds
    assert_includes lines.last.text, "D1"
  end

  def test_the_go_ahead_appends_one_line_and_a_second_call_none
    intent
    2.times { work.approve_intent("1") }

    assert_equal %w[opened approved], kinds
  end

  def test_a_verdict_appends_one_line_with_its_round
    intent
    work.add_verdict(intent_id: "1", verdict: "accept", findings: "checked")

    assert_equal %w[opened verdict], kinds
    assert_includes lines.last.text, "accept"
  end

  def test_abandoning_appends_an_abandoned_line
    intent
    work.note_intent(work_intent, "note", "why it ends")
    work.abandon_intent("1")

    assert_equal %w[opened noted abandoned], kinds
  end

  def test_parking_an_intent_that_is_not_in_progress_appends_no_line
    intent
    work.park_intent("1", "waits on review")

    assert_equal %w[opened], kinds
  end

  def test_a_note_appends_a_line_with_the_path_and_the_full_hash_of_the_document
    intent
    work.note_intent(work_intent, "note", "one line")
    line = lines.last

    assert_equal ["noted", "outcome.md", Digest::SHA256.hexdigest(graphs.retrieval.fetch("1", "outcome.md").body)], line.values_at(:kind, :path, :sha256)
  end

  def work_intent = graphs.retrieval.intent("1")

  def test_a_revision_appends_a_wrote_line_with_the_hash_of_the_new_revision
    intent
    work.revise_intent(work.revision(work_intent, "Beta", nil))
    line = lines.last

    assert_equal "wrote", line.kind
    assert_match(/\A\h{64}\z/, line.sha256)
  end

  def claimed
    intent
    work.add_node(intent_id: "1", title: "Build")
    work.claim_node(intent_id: "1", id: "n1", by: "s-1")
  end

  def test_a_claim_and_a_done_move_append_a_line_each_with_the_node
    claimed
    work.done_node(intent_id: "1", id: "n1", by: "s-1")

    assert_equal [%w[claimed n1], %w[done n1]], lines.drop(2).map { |line| line.values_at(:kind, :node) }
  end

  def test_renewing_a_claim_appends_no_line
    claimed
    before = lines.size
    work.renew_claims("s-1")

    assert_equal before, lines.size
  end

  def test_a_node_move_that_wrote_nothing_appends_no_line
    claimed
    work.done_node(intent_id: "1", id: "n1", by: "s-other")

    assert_equal %w[opened added claimed], kinds
  end

  def test_positions_count_up_from_one
    intent
    work.add_ruling(intent_id: "1", text: "a")

    assert_equal [1, 2], lines.map(&:position)
  end

  def test_an_intent_converted_from_savepoints_is_not_given_an_opened_line
    intent
    forget
    graphs.databases.fetch(:store).transaction { |batch| batch.put(:work_log, { intent_id: "1", position: 1, at: Plastic.timestamp(FixedClock::AT), kind: "noted", text: "old line" }) }
    work.add_ruling(intent_id: "1", text: "x")

    assert_equal %w[noted ruled], kinds
  end

  def test_the_go_ahead_line_belongs_to_the_session_that_gave_it
    intent
    graphs("s-2").work.approve_intent("1")

    assert_equal "s-2", lines.last.session_id
  end

  def test_a_legacy_intent_gets_no_line_until_a_real_write
    intent
    forget
    graphs.databases.fetch(:store).transaction { |batch| batch.put(:work_log, { intent_id: "1", position: 1, at: Plastic.timestamp(FixedClock::AT), kind: "noted", text: "old line" }) }

    assert_equal %w[noted], kinds
  end
end

# The owning rows and the work_log row land in one transaction, or neither lands.
class WorkLoggedWritesOneTransactionTest < Plastic::TestCase
  fixtures :empty

  OUTBOX_WORDS = /work_log_pending|write_id|drain_log/
  LIB = File.expand_path("../../../../lib", __dir__)
  FROZEN = File.join(LIB, "plastic/graph/schema/sequences")

  # A store whose work_log inserts fail, as on a full disk.
  class FailingLogStore < SimpleDelegator
    def transaction(*) = super { |batch| yield FailingLogBatch.new(batch) }
  end

  class FailingLogBatch < SimpleDelegator
    def put(table, *) = (table == :work_log) ? raise(Plastic::Graph::Database::Error, "disk full") : super
  end

  def failing
    open = graphs
    Plastic::Graph::GraphWriter.new(open.databases.merge(store: FailingLogStore.new(open.databases.fetch(:store))), folder:, retrieval: open.retrieval, session: "s-1")
  end

  def log_rows = graphs.databases.fetch(:store).rows("SELECT kind FROM work_log WHERE intent_id = '1'").map { |row| row["kind"] }

  def test_a_failing_work_log_insert_leaves_no_owning_row
    intent

    assert_raises(Plastic::Graph::Database::Error) { failing.add_ruling(intent_id: "1", text: "Flowbite styles every delivery") }
    assert_empty graphs.retrieval.rulings("1")
    assert_equal %w[opened], log_rows
  end

  def test_a_failing_owning_write_leaves_no_work_log_row
    intent

    assert_raises(Plastic::Invalid) { work.close_intent("1") }
    assert_equal %w[opened], log_rows
  end

  def test_one_write_adds_exactly_one_work_log_row
    intent
    work.add_ruling(intent_id: "1", text: "a")

    assert_equal %w[opened ruled], log_rows
  end

  def test_lib_and_the_schema_text_name_no_outbox_word
    named = Dir.glob(File.join(LIB, "**/*.rb")).reject { |path| path.start_with?(FROZEN) }.select { |path| File.read(path).match?(OUTBOX_WORDS) }

    assert_empty named.map { |path| path.delete_prefix("#{LIB}/") }
    assert_empty %i[knowledge work retrieval].select { |key| Plastic::Graph::Schema.fetch(key).match?(OUTBOX_WORDS) }
  end

  def graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)

  def work = graphs.work

  def intent(title = "Alpha") = work.write_intent(title:)
end
