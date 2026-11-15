# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncSecondHomeReachTest < Plastic::TestCase
  SecondHome = Plastic::Graph::Knowledge::Sync::SecondHome

  def test_a_second_home_that_is_not_active_reads_nothing
    none = SecondHome::NONE

    assert_equal [{}, [], nil], [none.problems, none.paths, none.cluster_read]
  end

  def test_a_context_json_of_an_archived_intent_listed_in_the_index_is_read
    write("store/index.json", JSON.generate("store" => "global", "origin_id" => "other-home", "clusters" => [],
      "intents" => [{ "intent_id" => "2", "origin_id" => "other-home", "slug" => "beta", "title" => "Beta", "status" => "done" }],
      "archives" => [{ "intent_id" => "2", "at" => STAMP, "session_id" => "s2", "completion" => nil }]))
    write("store/2--beta/context.json", JSON.generate("intent" => "2", "discovery" => { "a" => 1 }, "context" => { "b" => 2 }))

    assert_includes SecondHome.new(folder, retrieval).paths, "store/2--beta/context.json"
  end
end
