# frozen_string_literal: true

require_relative "../../../../test_helper"

# Step 27: the import of an old store that holds links ends with an index that lists them.
class KnowledgeSyncLegacyImportLinksTest < Plastic::TestCase
  fixtures :legacy

  def import
    sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases)
    Plastic::Graph::Knowledge::Sync::LegacyImport.new(sync, folder, retrieval, store_graphs.databases).call
  end

  def listed
    Array(JSON.parse(folder.read("store/index.json"))["links"]).map { |link| link.values_at("from_ref", "to_ref", "kind") }.sort
  end

  def held
    retrieval.every_link.map { |link| [link.from_ref, link.to_ref, link.kind] }.sort
  end

  def test_the_import_of_a_store_with_links_ends_with_an_index_that_lists_them_and_a_part_row
    import

    assert_equal [[%w[1 1a chain], %w[1 global:51 source], %w[1a 1 source]], held, true], [listed, listed, retrieval.printed.key?("store/index.json#links")]
  end
end
