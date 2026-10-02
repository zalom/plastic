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

  def test_successful_recovery_restores_the_original_tree
    with_importer do |_writer, folder|
      rollback = Plastic::Graph::ImportRollback.new(folder.root)
      assert_raises(RuntimeError) { rollback.call { damage(folder) } }
      assert_equal "original", folder.read("INDEX.md")
      assert_empty snapshots(folder)
    end
  end

  def test_failed_recovery_keeps_the_snapshot_and_reports_its_path
    with_importer do |_writer, folder|
      rollback = Plastic::Graph::ImportRollback.new(folder.root)
      File.stub(:rename, refuse_recovery(folder.root)) do
        error = assert_raises(Plastic::Invalid) { rollback.call { damage(folder) } }
        assert_recoverable(folder, error)
      end
    end
  end

  private

  def assert_recoverable(folder, error)
    original = File.join(snapshots(folder).fetch(0), "global", "INDEX.md")

    assert_equal "original", File.binread(original)
    assert_includes error.message, File.dirname(original)
  end

  def snapshots(folder) = Dir.glob(File.join(File.dirname(folder.root), ".plastic-import-*"))

  def damage(folder)
    folder.write("INDEX.md", "changed by failed import")
    raise "import failed"
  end

  def refuse_recovery(root)
    rename = File.method(:rename)
    lambda do |from, to|
      raise Errno::EACCES, "recovery blocked" if to == root

      rename.call(from, to)
    end
  end

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
