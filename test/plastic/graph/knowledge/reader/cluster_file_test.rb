# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderClusterFileTest < Plastic::TestCase
  fixtures :alpha

  ClusterFile = Plastic::Graph::Knowledge::Reader::ClusterFile

  def index(clusters) = JSON.generate({ "intents" => [], "clusters" => clusters })

  def apply(text) = store_graphs.databases[:work].transaction { |batch| ClusterFile.new(text.dup, origin).apply(batch) }

  def put(name, origin_id: nil)
    row = { name:, intent_id: "1" }
    store_graphs.databases[:work].transaction { |batch| batch.put(:clusters, origin_id ? row.merge(origin_id:) : row) }
  end

  def names(origin_id) = store_graphs.databases[:work].rows("SELECT name FROM clusters WHERE origin_id = :origin ORDER BY name", origin: origin_id).map { |row| row["name"] }

  def test_a_hand_edit_replaces_the_clusters_of_this_home
    put("Old")
    apply(index([{ "name" => "Core", "intents" => ["1"] }]))

    assert_equal %w[Core], names(origin)
  end

  def test_the_clusters_of_another_origin_stay
    put("Foreign", origin_id: "beef")
    apply(index([]))

    assert_equal %w[Foreign], names("beef")
  end

  def test_an_index_with_no_lists_clears_the_clusters_and_keeps_the_intents
    put("Old")
    apply("{}")

    assert_equal [[], "Alpha"], [names(origin), retrieval.intent("1").title]
  end

  def test_a_value_that_is_not_a_json_object_is_refused_with_its_reason
    error = assert_raises(Plastic::Invalid) { apply(index([5])) }

    assert_equal "store/index.json lists an entry under clusters that is not a JSON object", error.message
  end

  def test_a_cluster_whose_intents_is_no_list_is_refused_with_its_reason
    reasons = [[{ "name" => "c" }], [{ "name" => "c", "intents" => "1" }]].map { |clusters| assert_raises(Plastic::Invalid) { apply(index(clusters)) }.message }

    assert_equal ["store/index.json lists the cluster c with no list of intents"] * 2, reasons
  end
end
