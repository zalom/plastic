# frozen_string_literal: true

require "delegate"
require_relative "../../../../test_helper"

class KnowledgeLegacyImportCleanupTest < Plastic::TestCase
  # A store folder that refuses to delete a file.
  class LockedFolder < SimpleDelegator
    def delete(path) = raise(Errno::EACCES, path)
  end

  def setup
    super
    folder.write("INDEX.md", "original")
  end

  def cleanup(store_folder = folder) = Plastic::Graph::Knowledge::Legacy::ImportCleanup.new(store_folder, store_graphs.retrieval, @plastic_home)

  def test_with_the_flag_off_the_index_stays
    cleanup.call(Hash.new(0))

    assert_equal "original", folder.read("INDEX.md")
  end

  def test_with_the_flag_on_the_index_goes
    File.write(File.join(@plastic_home, "config.yml"), "migrate:\n  remove_after_import: true\n")
    cleanup.call(Hash.new(0))

    refute folder.exist?("INDEX.md")
  end

  def test_a_removal_that_stops_says_the_rows_were_imported
    File.write(File.join(@plastic_home, "config.yml"), "migrate:\n  remove_after_import: true\n")
    error = assert_raises(Plastic::Invalid) { cleanup(LockedFolder.new(folder)).call(Hash.new(0)) }

    assert_equal "global: imported, but removing the imported files stopped: Permission denied - INDEX.md", error.message
  end
end
