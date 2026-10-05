# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyStoreImportTest < Plastic::TestCase
  # A legacy reader that runs out of space halfway through the import.
  class FullReader
    def read_rows = raise(Errno::ENOSPC, "disk full")
  end

  def setup
    super
    folder.write("INDEX.md", "original")
  end

  def test_a_failed_import_refuses_and_names_the_cause
    error = assert_raises(Plastic::Invalid) { import.call }

    assert_includes error.message, "the import failed: No space left on device - disk full"
  end

  def test_a_failed_import_leaves_the_source_untouched
    assert_raises(Plastic::Invalid) { import.call }

    assert_equal "original", folder.read("INDEX.md")
  end

  private

  def import
    graphs = store_graphs
    Plastic::Graph::Knowledge::Legacy::StoreImport.new(FullReader.new, folder, graphs.retrieval, graphs.databases)
  end
end
