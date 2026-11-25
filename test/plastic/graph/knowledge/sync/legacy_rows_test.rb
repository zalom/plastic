# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncLegacyRowsTest < Plastic::TestCase
  fixtures :legacy

  def import
    graphs = Plastic::Graph.open(home: @plastic_home, store: "global", clock: FixedClock::CLOCK)
    sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval: graphs.retrieval, databases: graphs.databases)
    Plastic::Graph::Knowledge::Sync::LegacyImport.new(sync, folder, graphs.retrieval, graphs.databases).call
  end

  def test_every_imported_intent_is_stamped_with_the_time_of_the_clock
    import

    assert_equal [FixedClock::STAMP], retrieval.intents.map(&:updated_at).uniq
  end
end
