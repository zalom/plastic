# frozen_string_literal: true

require_relative "../support/kernel"

class SyncIndexTest < Minitest::Test
  include KernelFixtures::StoreCalls

  INDEX = "store/index.json"

  def setup
    super
    run_plastic("intent", "new", "Alpha")
  end

  def index = JSON.parse(File.read(store_path(INDEX)))

  def write_index(data) = File.write(store_path(INDEX), JSON.generate(data))

  def renamed_intents = index["intents"].map { |entry| entry.merge("title" => "Alpha, renamed") }

  # The title of intent 1 and the clusters, from the rows.
  def read_back
    retrieval = store_graphs.retrieval
    [retrieval.intent("1").title, retrieval.clusters.map { |cluster| [cluster.name, cluster.intent_id] }]
  end

  def test_a_hand_edit_of_index_json_reaches_the_rows
    write_index({ "intents" => renamed_intents, "clusters" => [{ "name" => "Core", "intents" => ["1"] }] })
    call = run_plastic("sync", "up")

    assert_equal 0, call.code, call.err
    assert_equal ["Alpha, renamed", [%w[Core 1]]], read_back
  end

  def test_an_intent_of_another_origin_is_refused
    data = index
    data["intents"][0]["origin_id"] = "0000beef"
    write_index(data)
    call = run_plastic("sync", "up")

    assert_equal 1, call.code
    assert_includes call.err, "lists 1 of origin 0000beef; a store holds only its own intents"
  end

  def test_index_json_that_does_not_parse_is_refused
    File.write(store_path(INDEX), "{")
    call = run_plastic("sync", "up")

    assert_equal 1, call.code
    assert_includes call.err, "store/index.json does not parse"
  end
end
