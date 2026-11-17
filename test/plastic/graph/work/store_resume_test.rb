# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/work/store_resume"

class WorkStoreResumeTest < Plastic::TestCase
  Folder = Struct.new(:intent_dirs)

  def resume(folder, session = "s-1") = Plastic::Graph::Work::StoreResume.new(retrieval, folder, session, now: Time.utc(2026, 11, 17, 8))

  def test_a_store_with_files_and_no_rows_asks_to_rebuild
    assert_equal "plastic sync up --project global", resume(Folder.new(["store/1--alpha"])).next_step.first
  end

  def test_a_store_with_no_rows_and_no_files_has_nothing_to_rebuild
    assert_equal [["store:", "global"], ["in play:", "none"]], resume(Folder.new([])).rows.first(2)
  end
end
