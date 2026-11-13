# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncArchivedIntentsTest < Plastic::TestCase
  OTHER = "other-home"

  def entry(**fields)
    { "intent_id" => "2", "origin_id" => OTHER, "parent_id" => nil, "ref" => nil, "slug" => "beta", "title" => "Beta", "kind" => "build",
      "status" => "done", "disposition" => "delivered", "reason" => nil, "opened_at" => STAMP, "closed_at" => STAMP }.merge(fields.transform_keys(&:to_s))
  end

  def completion(**fields)
    { "intent_id" => "2", "at" => STAMP, "session_id" => "s1", "judge" => "verdict", "criteria" => "{}", "evidence" => "{}",
      "outcome_sha256" => "abc" }.merge(fields.transform_keys(&:to_s))
  end

  def archived(kept: completion, at: STAMP) = { "intent_id" => "2", "at" => at, "session_id" => "s2", "completion" => kept }

  def write_index(intents: [entry], archives: [archived])
    write("store/index.json", JSON.generate({ "store" => "global", "origin_id" => OTHER, "intents" => intents, "archives" => archives, "clusters" => [] }))
  end

  def read_in = Plastic::Graph::Knowledge::Sync::ArchivedIntents.new(folder, retrieval).write_to(store_graphs.databases)

  def work_rows(sql) = store_graphs.databases.fetch(:work).rows(sql)

  def test_an_archive_entry_with_no_intent_row_inserts_the_intent_the_archive_and_the_completion
    write_index
    read_in

    found = ["intents", "archives", "completions"].map { |table| work_rows("SELECT intent_id, origin_id FROM #{table}").map(&:values) }

    assert_equal [[["2", retrieval.origin_id]]] * 3, found
    assert_equal [["done", "delivered"]], work_rows("SELECT status, disposition FROM intents").map(&:values)
  end

  def test_an_index_that_is_not_json_lists_no_archive
    write("store/index.json", "{not json")
    read_in

    assert_empty work_rows("SELECT * FROM archives")
  end

  def test_an_index_that_is_not_an_object_lists_no_archive
    write("store/index.json", "[]")
    read_in

    assert_empty work_rows("SELECT * FROM archives")
  end

  def test_an_archive_entry_with_no_completion_inserts_no_completion
    write_index(archives: [archived(kept: nil)])
    read_in

    assert_empty work_rows("SELECT * FROM completions")
  end

  def test_an_intent_that_already_has_a_row_keeps_its_row_and_gains_nothing
    open_intent("Mine")
    store_graphs.databases.fetch(:work).transaction { |batch| batch.write(:intents, "UPDATE intents SET intent_id = '2', slug = 'mine'") }
    write_index
    read_in

    assert_equal [["mine"]], work_rows("SELECT slug FROM intents").map(&:values)
    assert_empty work_rows("SELECT * FROM archives")
  end

  def test_a_restored_archive_row_survives_a_read
    write_index
    read_in
    store_graphs.databases.fetch(:work).transaction { |batch| batch.write(:archives, "UPDATE archives SET restored_at = '2026-11-01T00:00:00Z'") }
    read_in

    assert_equal [["2026-11-01T00:00:00Z"]], work_rows("SELECT restored_at FROM archives").map(&:values)
  end

  def test_a_second_read_changes_nothing
    write_index
    read_in
    before = [work_rows("SELECT * FROM intents"), work_rows("SELECT * FROM archives"), work_rows("SELECT * FROM completions")]
    read_in

    assert_equal before, [work_rows("SELECT * FROM intents"), work_rows("SELECT * FROM archives"), work_rows("SELECT * FROM completions")]
  end

  def test_a_store_with_no_index_inserts_nothing
    read_in

    assert_empty work_rows("SELECT * FROM archives")
  end

  def test_an_index_that_is_not_json_inserts_nothing
    write("store/index.json", "{not json")
    read_in

    assert_empty work_rows("SELECT * FROM archives")
  end

  def test_an_archive_entry_with_no_matching_intent_entry_inserts_nothing
    write_index(intents: [])
    read_in

    assert_empty work_rows("SELECT * FROM archives")
  end
end
