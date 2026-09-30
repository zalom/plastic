# frozen_string_literal: true

require_relative "../support/kernel"

class PrintsTest < Minitest::Test
  include KernelFixtures::StoreCalls

  FIELDS = %w[intent_id origin_id parent_id ref slug title kind status disposition opened_at closed_at].freeze

  def index_text = Plastic::Graph::Prints.index(store_graphs.retrieval).text

  def test_index_json_lists_intents_in_luhmann_order_with_every_field
    work = store_graphs.work
    %w[One Two].each { |title| work.write_intent(title:) }
    work.write_intent(title: "Child", parent_id: "1")
    index = JSON.parse(index_text)

    assert_equal %w[1 1a 2], index["intents"].map { |intent| intent["intent_id"] }
    assert_equal FIELDS, index["intents"].first.keys
    assert_equal "global", index["store"]
  end

  def test_clusters_list_their_intents
    store_graphs.work.write_intent(title: "One")
    store_graphs.databases[:work].transaction { |batch| batch.put(:clusters, { name: "Core", intent_id: "1" }) }

    assert_equal [{ "name" => "Core", "intents" => ["1"] }], JSON.parse(index_text)["clusters"]
  end

  def test_the_same_rows_print_the_same_bytes
    store_graphs.work.write_intent(title: "One")

    assert_equal index_text, index_text
  end

  def test_every_printed_file_has_its_hash_recorded
    graphs = store_graphs
    graphs.work.write_intent(title: "One")
    graphs.work.print_intent("1")
    printed = store_graphs.retrieval.printed

    %w[store/index.json store/1--one/1--one.md store/1--one/graph.json store/1--one/savepoint.md].each do |path|
      assert_equal Digest::SHA256.file(store_path(path)).hexdigest, printed.fetch(path)
    end
  end
end
