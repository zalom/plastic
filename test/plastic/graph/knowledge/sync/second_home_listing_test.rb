# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncSecondHomeListingTest < Plastic::TestCase
  include SecondHomeHelper

  fixtures :alpha_synced

  def rows_of_the_second_home
    { roadmap: retrieval.roadmap("plan")&.title, old: retrieval.roadmap("old"), batches: retrieval.batches("plan").map(&:position),
      items: retrieval.roadmap_items("plan").map(&:item), **context_rows }
  end

  def context_rows = { intents: retrieval.intents.map(&:intent_id), contexts: retrieval.contexts("1").size, discoveries: retrieval.discoveries("1").size }

  def test_the_clusters_are_read_while_another_part_is_broken
    write("roadmaps/old.md", "# Old\n")
    write("store/index.json", JSON.generate(JSON.parse(folder.read("store/index.json")).merge("clusters" => [{ "name" => "Core", "intents" => ["1"] }])))

    assert_equal "store/index.json", Plastic::Graph::Knowledge::Sync::SecondHome.new(folder, retrieval, nil).cluster_read.path
  end

  def test_a_broken_part_is_listed_and_every_good_part_is_read_into_every_table
    write(CONTEXT, context_json)
    write("roadmaps/old.md", "# Old\n")
    second_home_roadmap

    assert_equal %w[roadmaps/old.md], plan.unreadable_files.keys
    run_up

    assert_equal({ roadmap: "Plan", old: nil, batches: [1], items: %w[1], intents: ["1"], contexts: 1, discoveries: 1 }, rows_of_the_second_home)
    assert_equal %w[roadmaps/old.md], plan.unreadable_files.keys
  end

  def test_a_broken_part_is_counted_as_pending_only_for_what_is_still_to_read
    write("roadmaps/old.md", "# Old\n")
    second_home_roadmap

    assert_equal [1, 0], [plan.pending, run_up && plan.pending]
  end

  def test_only_the_files_of_a_second_home_are_files_this_home_holds_no_rows_for
    write("store/1--alpha/graph.json", "junk")
    write("roadmaps/old.md", "# Old\n")

    assert_equal [%w[roadmaps/old.md store/1--alpha/graph.json], %w[roadmaps/old.md]], [plan.unreadable_files.keys.sort, plan.rowless_files]
  end

  def test_the_overwrite_offered_for_a_file_this_home_holds_rows_for_prints_it_and_the_next_sync_up_reads_clean
    graph = "store/1--alpha/graph.json"
    write(graph, "junk")

    assert_equal [[graph], []], [plan.unreadable_files.keys, plan.rowless_files]
    sync.apply(sync.plan(:down, overwrite: graph))

    assert_empty sync.plan(:up).unreadable_files
  end

  def test_the_clusters_of_the_index_are_read_when_this_home_holds_none
    second_home = Plastic::Graph::Knowledge::Sync::SecondHome.new(folder, retrieval, nil)
    write("store/index.json", JSON.generate(JSON.parse(folder.read("store/index.json")).merge("clusters" => [{ "name" => "Core", "intents" => ["1"] }])))

    assert_equal "store/index.json", second_home.cluster_read.path
  end

  def test_a_cluster_that_names_an_intent_this_home_lacks_is_a_broken_part
    write("store/index.json", JSON.generate(JSON.parse(folder.read("store/index.json")).merge("clusters" => [{ "name" => "Core", "intents" => ["99"] }])))

    assert_includes plan.unreadable_files.fetch("store/index.json"), "99"
  end
end
