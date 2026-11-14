# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncHandEditsTest < Plastic::TestCase
  include LifecycleHelper

  def hand_edited(kinds, facts)
    Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases).hand_edited(kinds, facts)
  end

  def test_a_hand_edited_roadmap_is_given_the_reason_the_reader_refuses_it
    cli("roadmap", "new", "r1")
    write("roadmaps/r1.md", "# by hand\n")

    assert_equal({ "roadmaps/r1.md" => "roadmaps/r1.md is generated from rows; use the roadmap commands to change it" }, hand_edited([:roadmap], { slug: "r1" }))
  end

  def test_a_hand_edited_context_json_is_given_the_reason_the_reader_refuses_it
    specified
    cli("intent", "discover", "1", "spec")
    path = "#{retrieval.intent("1").dir}/context.json"
    write(path, File.read(store_path(path)).sub("{", "{\n  \"my_note\": \"keep this\","))

    assert_equal({ path => "context.json is generated from rows; use intent context and intent discover to change it" }, hand_edited([:intent], { intent_id: "1" }))
  end

  def test_an_index_that_another_home_printed_is_not_a_hand_edit
    specified
    index = JSON.parse(folder.read("store/index.json"))
    index.fetch("intents").each { |entry| entry["origin_id"] = "zzzz" }
    write("store/index.json", JSON.pretty_generate(index.merge("origin_id" => "zzzz")))

    assert_empty hand_edited([:intent], { intent_id: "1" })
  end

  def test_a_hand_edited_intent_file_that_reads_has_no_reason
    intent = specified
    write("#{intent.dir}/intent.md", "# by hand\n")

    assert_equal({ "#{intent.dir}/intent.md" => nil }, hand_edited([:intent], { intent_id: "1" }))
  end
end
