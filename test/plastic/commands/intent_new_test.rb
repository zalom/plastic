# frozen_string_literal: true

require_relative "../support/kernel"

class IntentNewTest < Minitest::Test
  include KernelFixtures::StoreCalls

  def origin = Plastic::Graph::Origin.new(@plastic_home).id

  def test_intent_new_writes_the_row_and_prints_the_files
    call = run_plastic("intent", "new", "Build", "the", "thing")
    intent = store_graphs.retrieval.intent("1")

    assert_equal 0, call.code, call.err
    assert_equal ["Build the thing", "build-the-thing", "open", origin], intent.to_h.values_at(:title, :slug, :status, :origin_id)
    %w[1--build-the-thing.md graph.json savepoint.md].each { |file| assert_path_exists store_path("store/1--build-the-thing/#{file}") }
    assert_equal ["1"], JSON.parse(File.read(store_path("store/index.json")))["intents"].map { |i| i["intent_id"] }
  end

  def test_the_report_names_each_database_written
    call = run_plastic("intent", "new", "Build")

    assert_includes call.out, "1 intent and 1 savepoint line in work_graph.db"
    assert_includes call.out, "1 document in knowledge_graph.db"
    assert_includes call.out, "next: plastic continue"
  end

  def test_a_child_takes_the_next_luhmann_id
    run_plastic("intent", "new", "Parent")
    run_plastic("intent", "new", "First", "child", "--parent", "1")
    call = run_plastic("intent", "new", "Second", "child", "--parent", "1")

    assert_equal 0, call.code, call.err
    assert_equal "1", store_graphs.retrieval.intent("1b").parent_id
    assert_path_exists store_path("store/1b--second-child/1b--second-child.md")
  end

  def test_a_missing_parent_fails
    call = run_plastic("intent", "new", "Orphan", "--parent", "9")

    assert_equal 1, call.code
    assert_includes call.err, "no intent 9"
  end

  def test_a_ref_is_kept_as_text
    call = run_plastic("intent", "new", "Ticketed", "--ref", "ENG-12")

    assert_equal 0, call.code, call.err
    assert_equal "ENG-12", store_graphs.retrieval.intent("1").ref
  end

  def test_a_ref_to_an_intent_of_this_installation_resolves
    run_plastic("intent", "new", "First")
    call = run_plastic("intent", "new", "Second", "--ref", "1-#{origin}")

    assert_equal 0, call.code, call.err
    assert_includes call.out, "intent 1 of this installation"
  end

  def test_a_ref_to_a_missing_intent_of_this_installation_fails
    run_plastic("intent", "new", "First")
    call = run_plastic("intent", "new", "Second", "--ref", "5-#{origin}")

    assert_equal 1, call.code
    assert_includes call.err, "no intent 5"
  end

  def test_a_status_outside_the_new_ones_fails
    call = run_plastic("intent", "new", "Late", "--status", "done")

    assert_equal 1, call.code
    assert_includes call.err, "open, active, parked or future"
  end

  def test_a_legacy_store_is_imported_first
    copy_legacy_store
    call = run_plastic("intent", "new", "Too", "soon")

    assert_equal 1, call.code
    assert_includes call.err, "plastic sync up"
    refute_path_exists store_path("store/index.json")
  end

  def test_a_hand_edit_of_index_json_is_read_first
    run_plastic("intent", "new", "First")
    File.write(store_path("store/index.json"), "{}\n")
    call = run_plastic("intent", "new", "Second")

    assert_equal 1, call.code
    assert_includes call.err, "store/index.json changed by hand"
  end
end
