# frozen_string_literal: true

require_relative "../../../../test_helper"

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
