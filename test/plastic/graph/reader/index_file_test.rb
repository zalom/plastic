# frozen_string_literal: true

require_relative "../../support/kernel"

class IndexFileTest < Minitest::Test
  include KernelFixtures::StoreGraphs

  IndexFile = Plastic::Graph::Reader::IndexFile

  def index(intents, clusters) = JSON.generate({ "intents" => intents, "clusters" => clusters })

  def entry(**fields) = retrieval.intent("1").index_h.merge(fields.transform_keys(&:to_s))

  def apply(text) = store_graphs.databases[:work].transaction { |batch| IndexFile.new(text.dup, origin).apply(batch) }

  def put_old_cluster = store_graphs.databases[:work].transaction { |batch| batch.put(:clusters, { name: "Old", intent_id: "1" }) }

  def test_a_hand_edit_renames_an_intent_and_replaces_the_clusters
    open_intent
    put_old_cluster
    apply(index([entry(title: "Renamed")], [{ "name" => "Core", "intents" => ["1"] }]))
    read = retrieval

    assert_equal ["Renamed", [%w[Core 1]]], [read.intent("1").title, read.clusters.map { |c| [c.name, c.intent_id] }]
  end

  def test_an_index_with_no_lists_clears_the_clusters
    open_intent
    put_old_cluster
    apply("{}")

    assert_equal [[], "Alpha"], [retrieval.clusters, retrieval.intent("1").title]
  end

  def test_an_intent_of_another_origin_is_refused
    file = IndexFile.new(index([{ "intent_id" => "1", "origin_id" => "beef" }], []), "a1b2")
    error = assert_raises(Plastic::Invalid) { file.apply(nil) }

    assert_equal "store/index.json lists 1 of origin beef; a store holds only its own intents", error.message
  end

  def test_an_intent_row_takes_every_index_field_and_a_fresh_time
    row = IndexFile.intent_row({ "intent_id" => "2", "title" => "T", "extra" => "x" })

    assert_equal %i[intent_id origin_id parent_id ref slug title kind status disposition opened_at closed_at updated_at], row.keys
    assert_equal ["2", "T", nil], row.values_at(:intent_id, :title, :kind)
    assert_match(/\A\d{4}-\d\d-\d\dT/, row[:updated_at])
  end
end
