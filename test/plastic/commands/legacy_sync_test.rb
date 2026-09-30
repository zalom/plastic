# frozen_string_literal: true

require_relative "../support/kernel"

class LegacySyncTest < Minitest::Test
  include KernelFixtures::StoreCalls

  DIR = "store/1--ai-infra"

  def setup
    super
    copy_legacy_store
  end

  def test_sync_up_imports_a_legacy_store_and_deletes_index_md
    call = run_plastic("sync", "up")
    retrieval = store_graphs.retrieval

    assert_equal 0, call.code, call.err
    refute_path_exists store_path("INDEX.md")
    assert_equal [%w[1 active], %w[1a future]], retrieval.intents.map { |intent| [intent.intent_id, intent.status] }
    assert_equal "1", retrieval.intent("1a").parent_id
    assert_equal %w[1 1a], JSON.parse(File.read(store_path("store/index.json")))["intents"].map { |i| i["intent_id"] }
  end

  def test_every_file_of_an_intent_folder_reaches_rows
    run_plastic("sync", "up")
    retrieval = store_graphs.retrieval

    assert_equal %w[1--ai-infra.md checklist.md outcome.md plan.md spec.md], retrieval.documents("1").map(&:path)
    assert_equal ["#{DIR}/actions/.gitkeep"], retrieval.kept_files("1").map(&:name)
    assert_equal "What  1--ai-infra.md", sole(retrieval.savepoints("1")).text
  end

  def test_the_documents_print_back_byte_for_byte
    original = snapshot(store_path(DIR))
    run_plastic("sync", "up")
    printed = snapshot(store_path(DIR))

    assert_equal original, printed.slice(*original.keys)
    assert_includes printed.keys, "graph.json"
  end

  def test_an_imported_intent_folder_rebuilds_the_same
    run_plastic("sync", "up")
    before = snapshot(store_path(DIR))
    FileUtils.rm_rf(store_path(DIR))
    call = run_plastic("sync", "down")

    assert_equal 0, call.code, call.err
    assert_equal before, snapshot(store_path(DIR))
  end

  def test_a_second_sync_up_is_not_legacy
    run_plastic("sync", "up")
    call = run_plastic("sync", "up")

    assert_equal 0, call.code, call.err
    refute_includes call.out, "INDEX.md"
  end
end
