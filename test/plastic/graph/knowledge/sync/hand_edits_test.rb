# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncHandEditsTest < Plastic::TestCase
  include LifecycleHelper

  def hand_edited(kinds, facts)
    Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases).hand_edited(kinds, facts)
  end

  def test_a_hand_edited_context_json_that_reads_has_no_reason
    specified
    cli("intent", "discover", "1", "spec")
    path = "#{retrieval.intent("1").dir}/context.json"
    write(path, File.read(store_path(path)).sub("{", "{\n  \"my_note\": \"keep this\","))

    assert_equal({ path => nil }, hand_edited([:intent], { intent_id: "1" }))
  end

  def test_an_index_that_another_home_printed_is_a_hand_edit_that_reads_on_a_home_that_holds_a_print_of_it
    specified
    index = JSON.parse(folder.read("store/index.json"))
    index.fetch("intents").each { |entry| entry["origin_id"] = "zzzz" }
    write("store/index.json", JSON.pretty_generate(index.merge("origin_id" => "zzzz")))

    assert_equal({ "store/index.json" => nil }, hand_edited([:intent], { intent_id: "1" }))
  end

  def test_a_hand_edited_intent_file_that_reads_has_no_reason
    intent = specified
    write("#{intent.dir}/intent.md", "# by hand\n")

    assert_equal({ "#{intent.dir}/intent.md" => nil }, hand_edited([:intent], { intent_id: "1" }))
  end

  def test_a_core_file_that_no_row_holds_is_a_hand_edit
    intent = open_intent
    write("#{intent.dir}/outcome.md", "# Outcome\n\nBy hand.\n")

    assert_equal({ "#{intent.dir}/outcome.md" => nil }, hand_edited([:intent], { intent_id: "1" }))
  end

  def test_a_core_file_that_no_row_holds_and_sync_up_cannot_read_has_no_reason
    intent = open_intent
    path = "#{intent.dir}/context.json"
    write(path, "not json\n")
    reason = Plastic::Graph::Knowledge::Sync::Readability.new(folder, retrieval, store_graphs.databases).call([path])

    assert_equal [true, { path => nil }], [reason.key?(path), hand_edited([:intent], { intent_id: "1" })]
  end

  def test_a_file_outside_the_core_files_that_no_row_holds_is_no_hand_edit
    intent = open_intent
    write("#{intent.dir}/resources/output/reports/page.html", "<p>page</p>\n")

    assert_equal({}, hand_edited([:intent], { intent_id: "1" }))
  end
end
