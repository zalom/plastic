# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyImportMetadataTest < Plastic::TestCase
  fixtures :legacy

  def import
    graphs = Plastic::Graph.open(home: @plastic_home, store: "global", clock: FixedClock::CLOCK)
    sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval: graphs.retrieval, databases: graphs.databases)
    Plastic::Graph::Knowledge::Sync::LegacyImport.new(sync, folder, graphs.retrieval, graphs.databases).call
  end

  def test_the_import_reports_the_metadata_it_wrote
    assert_match(/\Aimported metadata: /, import.last)
  end

  def test_the_decisions_of_the_intent_files_are_read_into_rulings
    write("store/1--alpha-service/spec.md", "# Spec\n\n## Decisions\n- Ship it\n")
    import

    assert_equal ["Ship it"], retrieval.rulings("1").map(&:text)
  end
end
