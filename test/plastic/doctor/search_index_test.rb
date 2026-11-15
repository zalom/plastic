# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/doctor/search_index"

class DoctorSearchIndexTest < Plastic::TestCase
  # A retrieval graph that answers a report and a repair as the test sets them.
  Retrieval = Struct.new(:report, :repair_error) do
    def search_index_report = report

    def repair = (raise repair_error if repair_error)
  end

  def setup
    super
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "alpha"))
    FileUtils.touch(File.join(@plastic_home, "stores", "alpha", "knowledge_graph.db"))
  end

  def check(retrieval) = Plastic::Doctor::SearchIndex.new(@plastic_home, "alpha", opener: ->(_home, _slug) { retrieval }).check

  def test_a_store_held_by_another_process_fails_as_not_checked
    held = Class.new { def search_index_report = raise(Plastic::Graph::Database::Error, "knowledge_graph.db: database is locked") }.new

    assert_equal [["search index alpha:", "not checked, the database is held by another process"], true], check(held).then { |row| [row.to_a.first(2), !row.repair.nil?] }
  end

  def test_a_store_that_cannot_be_written_and_is_out_of_step_fails_as_not_rebuilt
    retrieval = Retrieval.new({ repairable: true, missing: [] }, Plastic::Graph::Database::Error.new("knowledge_graph.db: attempt to write a readonly database"))

    assert_equal "out of step, not rebuilt, the store cannot be written", check(retrieval).value
  end

  def test_a_store_that_cannot_be_written_and_matches_says_in_step
    retrieval = Retrieval.new({ repairable: false, missing: [] }, Plastic::Graph::Database::Error.new("readonly"))

    assert_equal ["ok, in step", nil], check(retrieval).then { |row| [row.value, row.repair] }
  end

  def test_a_repair_that_fails_for_another_reason_is_raised
    retrieval = Retrieval.new({ repairable: true, missing: [] }, Plastic::Graph::Database::Error.new("knowledge_graph.db: disk image is malformed"))

    assert_raises(Plastic::Graph::Database::Error) { check(retrieval) }
  end

  def test_a_report_that_fails_for_another_reason_is_raised
    broken = Class.new { def search_index_report = raise(Plastic::Graph::Database::Error, "knowledge_graph.db: disk image is malformed") }.new

    assert_raises(Plastic::Graph::Database::Error) { check(broken) }
  end

  def test_one_lost_document_is_named_in_the_singular
    assert_equal "the evidence of 1 document is lost; no rebuild brings it back", check(Retrieval.new({ repairable: false, missing: ["plan.md"] })).value
  end

  def test_two_lost_documents_are_named_in_the_plural
    assert_equal "the evidence of 2 documents are lost; no rebuild brings it back", check(Retrieval.new({ repairable: false, missing: %w[a.md b.md] })).value
  end

  def test_a_store_folder_with_files_and_no_database_says_so
    File.delete(File.join(@plastic_home, "stores", "alpha", "knowledge_graph.db"))
    FileUtils.touch(File.join(@plastic_home, "stores", "alpha", "plan.md"))

    assert_equal "ok, no database in this store", check(nil).value
  end

  def test_a_store_folder_that_does_not_exist_prints_no_row
    assert_nil Plastic::Doctor::SearchIndex.new(@plastic_home, "beta", opener: ->(_home, _slug) {}).check
  end
end
