# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require "tempfile"

module IntentContextTestSupport
  private

  def write_document(store, body)
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:knowledge), origin).write("1", "evidence.md", body)
    graphs.retrieval.backfill
    graphs.retrieval.archived?("1")
    graphs.retrieval.reference("1", "evidence.md").fetch(:uri)
  end

  def context_submission(reference)
    { "evidence" => [reference], "facts" => ["a source fact"], "interpretations" => ["an agent interpretation"],
      "gaps" => ["a remaining gap"], "rulings" => ["an owner ruling"] }
  end

  def archive_source_intent
    source = Plastic::Graph.open(home: @plastic_home, store: "other")
    source.databases.fetch(:work).transaction do |batch|
      batch.put(:archives, { intent_id: "1", at: Plastic.now, restored_at: nil, session_id: "context-test" })
    end
  end

  def discovered_reference
    open_intent
    reference = write_document("other", "selected evidence")
    plastic("intent", "discover", "1", "selected", "--source-project", "other", table: Plastic::CLI::TABLE)
    reference
  end

  def remove_selected_revision
    Plastic::Graph.open(home: @plastic_home, store: "other").databases.fetch(:knowledge).transaction do |batch|
      batch.add("DELETE FROM document_revisions WHERE intent_id = '1' AND path = 'evidence.md' AND origin_id = :origin", origin: origin)
    end
  end

  def remove_current_head
    graphs = Plastic::Graph.open(home: @plastic_home, store: "other")
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:knowledge), origin).remove("1", "evidence.md")
  end

  def mark_retrieval_incomplete
    graphs = Plastic::Graph.open(home: @plastic_home, store: "other")
    graphs.databases.fetch(:knowledge).transaction do |batch|
      batch.add("UPDATE retrieval_backfills SET version = 0 WHERE name = 'retrieval' AND origin_id = :origin", origin: origin)
    end
  end

  def submit_context(submission, json: false)
    Tempfile.create(["context", ".json"]) do |file|
      file.write(JSON.generate(submission))
      file.flush
      arguments = ["intent", "context", "1", "--from", file.path]
      arguments << "--json" if json
      result = plastic(*arguments, table: Plastic::CLI::TABLE)

      assert_equal 0, result.code, result.err
      return JSON.parse(result.out).fetch("result").fetch("context") if json
    end
  end

  def read_context
    result = plastic("intent", "context", "1", "--json", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    JSON.parse(result.out).fetch("result").fetch("context")
  end

  def submit_raw_context(body)
    Tempfile.create(["context", ".json"]) do |file|
      file.write(body)
      file.flush
      return plastic("intent", "context", "1", "--from", file.path, table: Plastic::CLI::TABLE)
    end
  end
end

module IntentContextAssertionSupport
  private

  def assert_persisted_context(submission, submitted, readback)
    fields = %w[evidence facts interpretations gaps rulings]

    assert_equal submission, submitted.slice(*fields)
    assert_equal submission, readback.slice(*fields)
    row = Plastic::Graph.open(home: @plastic_home, store: "global").databases.fetch(:knowledge).row("SELECT data FROM retrieval_contexts WHERE intent_id = '1'")
    persisted = submitted.slice(*fields, "archive_states", "intent_id", "discovery")

    assert_equal persisted, JSON.parse(row.fetch("data"))
  end

  def assert_archived_context(fresh, stale, reference)
    fresh_evidence = evidence_freshness(fresh)
    stale_evidence = evidence_freshness(stale)

    refute fresh_evidence.fetch("archived")
    assert_equal "stale", stale_evidence.fetch("state")
    assert stale_evidence.fetch("archived")
    document = Plastic::Graph.open(home: @plastic_home, store: "other").retrieval.fetch_reference(reference)

    assert_equal "selected evidence", document.fetch(:body)
  end

  def evidence_freshness(context)
    context.fetch("freshness").fetch("evidence").first
  end

  def assert_context_remains(before, result)
    assert_equal 2, result.code
    assert_equal before.slice("evidence", "facts"), read_context.slice("evidence", "facts")
  end
end

class IntentContextPersistenceTest < Plastic::TestCase
  include IntentContextTestSupport
  include IntentContextAssertionSupport

  def test_validates_and_persists_agent_selected_evidence_without_writing_source_stores
    reference = discovered_reference
    before = File.binread(File.join(@plastic_home, "stores", "other", "knowledge_graph.db"))
    submission = context_submission(reference)
    submitted = submit_context(submission, json: true)
    readback = read_context

    assert_persisted_context(submission, submitted, readback)
    assert_equal before, File.binread(File.join(@plastic_home, "stores", "other", "knowledge_graph.db"))
  end

  def test_keeps_context_categories_separate_and_reports_changed_heads
    open_intent
    reference = write_document("other", "first selected evidence")
    plastic("intent", "discover", "1", "selected", "--source-project", "other", table: Plastic::CLI::TABLE)
    submission = context_submission(reference)
    submit_context(submission)
    write_document("other", "second selected evidence")
    context = read_context

    assert_equal submission.slice("facts", "interpretations", "gaps", "rulings"), context.slice("facts", "interpretations", "gaps", "rulings")
    assert_equal [{ "uri" => reference, "state" => "stale", "archived" => false }], context.fetch("freshness").fetch("evidence")
  end

  def test_records_selected_archive_state_and_marks_it_stale_without_losing_the_pinned_revision
    reference = discovered_reference
    submit_context(context_submission(reference))

    fresh = read_context
    archive_source_intent
    stale = read_context

    assert_archived_context(fresh, stale, reference)
  end

  def test_reports_a_removed_current_head_as_stale_when_its_pinned_revision_survives
    reference = discovered_reference
    submit_context(context_submission(reference))
    remove_current_head

    assert_equal "stale", read_context.fetch("freshness").fetch("evidence").first.fetch("state")
  end

  def test_reports_selected_evidence_as_missing_when_its_pinned_revision_is_removed
    reference = discovered_reference
    submit_context(context_submission(reference))
    remove_current_head
    remove_selected_revision

    assert_equal "missing", read_context.fetch("freshness").fetch("evidence").first.fetch("state")
  end

  def test_reads_the_saved_context_file_when_the_database_record_is_absent
    reference = discovered_reference
    submission = context_submission(reference)
    submit_context(submission)
    Plastic::Graph.open(home: @plastic_home, store: "global").databases.fetch(:knowledge).transaction do |batch|
      batch.add("DELETE FROM retrieval_contexts WHERE intent_id = :intent_id", intent_id: "1")
    end

    assert_equal submission.slice("evidence", "facts", "interpretations", "gaps", "rulings"),
      read_context.slice("evidence", "facts", "interpretations", "gaps", "rulings")
  end
end

module IntentContextValidationAssertions
  def assert_invalid_submission(document, code, message)
    result = submit_raw_context(JSON.generate(document))

    assert_equal code, result.code
    assert_includes result.err, message
  end
end

class IntentContextValidationTest < Plastic::TestCase
  include IntentContextValidationAssertions
  include IntentContextTestSupport
  include IntentContextAssertionSupport

  def test_reports_retrieval_maintenance_when_a_selected_source_is_not_ready
    reference = discovered_reference
    submit_context(context_submission(reference))
    mark_retrieval_incomplete
    before = File.binread(store_path("../other/knowledge_graph.db"))

    result = plastic("intent", "context", "1", table: Plastic::CLI::TABLE)

    assert_equal 1, result.code
    assert_includes result.err, "retrieval maintenance is required before source other can be read"
    assert_equal before, File.binread(store_path("../other/knowledge_graph.db"))
  end

  def test_rejects_an_invalid_owning_intent_id_before_reading_context
    result = plastic("intent", "context", "not-an-id", table: Plastic::CLI::TABLE)

    assert_equal 2, result.code
    assert_includes result.err, "invalid intent id"
  end

  def test_reports_when_an_owning_intent_has_no_saved_retrieval_context
    open_intent

    result = plastic("intent", "context", "1", table: Plastic::CLI::TABLE)

    assert_equal 1, result.code
    assert_includes result.err, "no retrieval context for intent 1"
  end

  def test_reports_malformed_context_submission_json_as_usage_without_writing_context
    open_intent
    write_document("other", "selected evidence")
    plastic("intent", "discover", "1", "selected", "--source-project", "other", table: Plastic::CLI::TABLE)

    result = submit_raw_context("{")

    assert_equal 2, result.code
    refute_path_exists store_path("context/1.json")
  end

  def test_rejects_an_unknown_owning_intent_id_before_reading_context
    result = plastic("intent", "context", "99", table: Plastic::CLI::TABLE)

    assert_equal 1, result.code
    assert_includes result.err, "no intent 99 in owning store"
  end

  def test_does_not_recreate_a_missing_selected_source_work_database
    reference = discovered_reference
    submit_context(context_submission(reference))
    path = store_path("../other/work_graph.db")
    File.delete(path)

    result = plastic("intent", "context", "1", table: Plastic::CLI::TABLE)

    assert_equal 1, result.code
    refute_path_exists path
  end

  def test_rejects_a_non_object_submission_without_replacing_saved_context
    reference = discovered_reference
    submit_context(context_submission(reference))
    before = File.binread(store_path("context/1.json"))

    result = submit_raw_context("[]")

    assert_equal 2, result.code
    assert_equal before, File.binread(store_path("context/1.json"))
  end

  def test_rejects_non_array_context_categories_without_replacing_saved_context
    reference = discovered_reference
    submit_context(context_submission(reference))
    before = read_context
    invalid = context_submission(reference).merge("facts" => "not an array")

    result = submit_raw_context(JSON.generate(invalid))

    assert_context_remains(before, result)
    assert_includes result.err, "must be arrays"
  end

  def test_rejects_evidence_that_was_not_discovered
    reference = discovered_reference
    undiscovered = context_submission(reference).merge("evidence" => ["plastic://other/1/missing.md"])

    assert_invalid_submission(undiscovered, 1, "evidence was not discovered")
  end

  def test_rejects_an_unpinned_reference_from_a_legacy_discovery_record
    reference = discovered_reference
    submit_context(context_submission(reference))
    before = read_context
    unpinned = reference.sub(/\?revision=[0-9a-f]{64}\z/, "")
    store_legacy_discovery(unpinned)

    result = submit_raw_context(JSON.generate(context_submission(unpinned)))

    assert_equal 1, result.code
    assert_legacy_context_preserved(before, result)
  end

  private

  def assert_legacy_context_preserved(before, result)
    assert_equal before.slice("evidence", "facts"), read_context.slice("evidence", "facts")
    assert_includes result.err, "evidence revision changed"
  end

  def store_legacy_discovery(reference)
    document = { "query" => "selected", "scope" => ["other"], "candidates" => [{ "uri" => reference }] }
    Plastic::Graph.open(home: @plastic_home, store: "global").databases.fetch(:knowledge).transaction do |batch|
      batch.put(:retrieval_discoveries, { intent_id: "1", data: JSON.generate(document), updated_at: Plastic.now })
    end
  end
end

class IntentContextStoredFieldsTest < Plastic::TestCase
  include IntentContextTestSupport

  def test_stores_only_the_context_fields_and_drops_anything_else_the_file_carries
    reference = discovered_reference
    submission = context_submission(reference).merge("architecture" => { "provider" => "external" })

    submit_context(submission)

    refute read_context.key?("architecture")
    refute_path_exists store_path("architecture")
  end
end
