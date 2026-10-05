# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/retrieval/source"

class RetrievalSourceTest < Plastic::TestCase
  def test_the_retrieval_source_reads_the_intents_of_its_store
    store_graphs.work.write_intent(title: "Alpha")

    assert_equal ["Alpha"], Plastic::Graph.open_retrieval(home: @plastic_home, store: "global").intents.map(&:title)
  end

  def test_the_retrieval_source_names_its_store_and_origin
    read = Plastic::Graph::Retrieval::Source.open(home: @plastic_home, store: "global")

    assert_equal ["global", origin], [read.store, read.origin_id]
  end
end
