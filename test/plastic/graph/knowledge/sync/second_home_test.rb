# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncSecondHomeTest < Plastic::TestCase
  include SecondHomeHelper

  fixtures :alpha_synced

  def test_a_context_json_with_a_row_is_not_read_again_by_the_second_home
    write(CONTEXT, context_json)
    run_up

    assert_empty Plastic::Graph::Knowledge::Sync::SecondHome.new(folder, retrieval).paths
  end

  def test_a_context_json_with_no_row_is_read_into_the_context_and_discovery_rows
    write(CONTEXT, context_json)

    assert_includes run_up, "read #{CONTEXT}"
    assert_equal [{ "a" => 1 }, { "b" => 2 }], [JSON.parse(structure.discoveries("1").first.data), JSON.parse(structure.contexts("1").first.data)]
  end

  def test_a_context_json_with_a_row_that_differs_from_its_print_replaces_the_row
    write(CONTEXT, context_json)
    run_up
    write(CONTEXT, context_json(context: { "b" => 3 }))
    run_up

    assert_equal({ "b" => 3 }, JSON.parse(structure.contexts("1").first.data))
  end
end

class KnowledgeSyncSecondHomeListingTest < Plastic::TestCase
  include SecondHomeHelper

  fixtures :alpha_synced

  def context_rows = { intents: retrieval.intents.map(&:intent_id), contexts: structure.contexts("1").size, discoveries: structure.discoveries("1").size }

  def test_a_broken_part_is_listed_and_every_good_part_is_read_into_every_table
    write(CONTEXT, "{nope")
    write("store/1--alpha/graph.json", "junk")

    assert_equal [CONTEXT, "store/1--alpha/graph.json"], plan.unreadable_files.keys.sort
    run_up

    assert_equal [CONTEXT, "store/1--alpha/graph.json"], plan.unreadable_files.keys.sort
    assert_equal({ intents: ["1"], contexts: 0, discoveries: 0 }, context_rows)
  end

  def test_the_overwrite_offered_for_a_file_this_home_holds_rows_for_prints_it_and_the_next_sync_up_reads_clean
    graph = "store/1--alpha/graph.json"
    write(graph, "junk")

    assert_equal [[graph], []], [plan.unreadable_files.keys, plan.rowless_files]
    sync.apply(sync.plan(:down, overwrite: graph))

    assert_empty sync.plan(:up).unreadable_files
  end

  def test_a_cluster_that_names_an_intent_this_home_lacks_is_a_broken_part
    write("store/index.json", JSON.generate(JSON.parse(folder.read("store/index.json")).merge("clusters" => [{ "name" => "Core", "intents" => ["99"] }])))

    assert_includes plan.unreadable_files.fetch("store/index.json"), "99"
  end
end

class KnowledgeSyncSecondHomeReachTest < Plastic::TestCase
  fixtures :alpha_synced

  SecondHome = Plastic::Graph::Knowledge::Sync::SecondHome

  def test_a_second_home_that_is_not_active_reads_nothing
    none = SecondHome::NONE

    assert_equal [{}, [], 0], [none.problems, none.paths, none.size]
  end

  def test_a_context_json_of_an_archived_intent_listed_in_the_index_is_read
    write("store/index.json", JSON.generate("store" => "global", "origin_id" => "other-home", "clusters" => [],
      "intents" => [{ "intent_id" => "2", "origin_id" => "other-home", "slug" => "beta", "title" => "Beta", "status" => "done" }],
      "archives" => [{ "intent_id" => "2", "at" => STAMP, "session_id" => "s2", "completion" => nil }]))
    write("store/2--beta/context.json", JSON.generate("intent" => "2", "discovery" => { "a" => 1 }, "context" => { "b" => 2 }))

    assert_includes SecondHome.new(folder, retrieval).paths, "store/2--beta/context.json"
  end

  def test_a_second_home_with_clusters_counts_only_its_paths_because_the_clusters_are_a_part_entry
    write("store/index.json", JSON.generate(JSON.parse(folder.read("store/index.json")).merge("clusters" => [{ "name" => "Core", "intents" => ["1"] }])))

    assert_equal 0, SecondHome.new(folder, retrieval).size
  end
end

class KnowledgeSyncSecondHomeUnreadableTest < Plastic::TestCase
  include SecondHomeHelper

  fixtures :alpha_synced

  def test_a_context_json_that_is_not_json_is_a_broken_part_left_as_it_is
    write(CONTEXT, "{nope")

    assert_includes plan.unreadable_files.fetch(CONTEXT), "not JSON"
    run_up

    assert_equal [[], "{nope"], [structure.contexts("1"), folder.read(CONTEXT)]
  end

  def test_a_context_json_that_names_another_intent_is_a_broken_part
    write(CONTEXT, context_json(intent: "2"))

    assert_includes plan.unreadable_files.fetch(CONTEXT), "intent 2"
  end

  def test_every_broken_part_is_named_in_one_run
    write(CONTEXT, "{nope")
    write("store/1--alpha/graph.json", "junk")

    assert_equal [CONTEXT, "store/1--alpha/graph.json"], plan.unreadable_files.keys.sort
  end
end

class KnowledgeSyncSecondHomeIdleTest < Plastic::TestCase
  def test_the_idle_home_has_no_problem_no_path_and_no_size
    home = Plastic::Graph::Knowledge::Sync::SecondHome::NONE

    assert_equal [{}, [], 0], [home.problems, home.paths, home.size]
  end
end
