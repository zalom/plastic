# frozen_string_literal: true

require "minitest/mock"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic"
require_relative "../../../scripts/lib/plastic/graph"

class LegacyStoreImportSafetyTest < Minitest::Test
  def test_a_failed_snapshot_does_not_remove_the_source
    with_importer do |writer, folder|
      FileUtils.stub(:cp_r, method(:fail_snapshot)) do
        error = assert_raises(Plastic::Invalid) { writer.call }
        assert_includes error.message, "snapshot full"
      end
      assert_equal "original", folder.read("INDEX.md")
    end
  end

  private

  def fail_snapshot(source, destination)
    FileUtils.mkdir_p(File.join(destination, File.basename(source)))
    raise Errno::ENOSPC, "snapshot full"
  end

  def with_importer
    Dir.mktmpdir("plastic-import-safety") do |home|
      graphs = Plastic::Graph.open(home:, store: "global")
      folder = Plastic::Graph::StoreFolder.new(File.join(home, "stores", "global"))
      folder.write("INDEX.md", "original")
      writer = Plastic::Graph::LegacyStoreImport.new(nil, folder, graphs.retrieval, graphs.databases)
      yield writer, folder
    end
  end
end
