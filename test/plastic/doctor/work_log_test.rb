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

  def test_a_line_a_failed_write_left_out_is_added
    store_graphs.work.write_intent(title: "One")
    store_graphs.databases[:work].transaction { |batch| batch.remove(:work_log, intent_id: "1") }

    assert_equal "ok, added 1 missing line", check.value
    assert_equal ["opened"], store_graphs.retrieval.work_log("1").map(&:kind)
  end
end
