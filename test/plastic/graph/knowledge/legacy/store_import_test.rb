# frozen_string_literal: true

require "delegate"
require_relative "../../../../test_helper"

class KnowledgeLegacyStoreImportTest < Plastic::TestCase
  # A legacy reader that runs out of space halfway through the import.
  class FullReader
    def read_rows = raise(Errno::ENOSPC, "disk full")
  end

  # A legacy reader with nothing left to read.
  class EmptyReader
    def read_rows = []
  end

  # A store folder that refuses to delete a file.
  class LockedFolder < SimpleDelegator
    def delete(path) = raise(Errno::EACCES, path)
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

  def test_a_removal_that_stops_says_the_rows_were_imported
    File.write(File.join(@plastic_home, "config.yml"), "migrate:\n  remove_after_import: true\n")
    graphs = store_graphs
    import = Plastic::Graph::Knowledge::Legacy::StoreImport.new(EmptyReader.new, LockedFolder.new(folder), graphs.retrieval, graphs.databases)

    error = assert_raises(Plastic::Invalid) { import.call }

    assert_equal "global: imported, but removing the imported files stopped: Permission denied - INDEX.md", error.message
  end

  private

  def import
    graphs = store_graphs
    Plastic::Graph::Knowledge::Legacy::StoreImport.new(FullReader.new, folder, graphs.retrieval, graphs.databases)
  end
end
