# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/doctor/work_log"

class DoctorWorkLogTest < Plastic::TestCase
  def check = Plastic::Doctor::WorkLog.new(@plastic_home, "global").check

  def test_a_store_with_no_folder_has_no_row
    assert_nil Plastic::Doctor::WorkLog.new(@plastic_home, "absent").check
  end

  def test_a_store_with_no_work_database_says_so
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "alpha"))

    assert_equal "ok, no database in this store", Plastic::Doctor::WorkLog.new(@plastic_home, "alpha").check.value
  end

  def test_an_intent_with_every_line_is_left_alone
    store_graphs.work.write_intent(title: "One")

    assert_equal ["work log global:", "ok, every intent has its lines"], check.to_a.first(2)
  end

  class Died < StandardError; end

  class DiesAfterCommit < Plastic::Graph::Work::Log
    def drain(intent_id)
      @calls = @calls.to_i + 1
      (@calls == 2) ? raise(Died, "the process died after the owning commit") : super
    end
  end

  def leave_pending(intent_id, text)
    open = store_graphs
    log = DiesAfterCommit.new(open.databases, open.retrieval, session: "s-dead")
    work = Plastic::Graph::WorkGraph.new(open.databases, folder:, retrieval: open.retrieval, session: "s-dead", log:)
    assert_raises(Died) { work.add_ruling(intent_id:, text:) }
  end

  def ruled_lines(id) = store_graphs.retrieval.work_log(id)

  def test_a_write_that_died_after_its_commit_is_drained_and_the_intent_is_named
    store_graphs.work.write_intent(title: "One")
    store_graphs.work.write_intent(title: "Two")
    leave_pending("2", "kept")

    assert_equal "ok, drained 1 work log line: intent 2", check.value
    assert_equal [%w[opened ruled], ["s-dead"]], [ruled_lines("2").map(&:kind), ruled_lines("2").last(1).map(&:session_id)]
  end

  def test_a_second_check_adds_nothing
    store_graphs.work.write_intent(title: "One")
    leave_pending("1", "kept")
    check

    assert_equal "ok, every intent has its lines", check.value
    assert_equal %w[opened ruled], store_graphs.retrieval.work_log("1").map(&:kind)
  end

  def convert_to_old_line
    work = store_graphs.databases.fetch(:store)
    work.transaction { |batch| batch.remove(:work_log, intent_id: "1") }
    work.transaction { |batch| batch.put(:work_log, { intent_id: "1", position: 1, at: Plastic.now, kind: "noted", text: "old line" }) }
  end

  def test_a_converted_store_gets_no_line_from_the_check
    store_graphs.work.write_intent(title: "One")
    convert_to_old_line

    assert_equal ["ok, every intent has its lines", %w[noted]], [check.value, ruled_lines("1").map(&:kind)]
  end
end
