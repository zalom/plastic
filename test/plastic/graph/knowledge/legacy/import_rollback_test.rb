# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyImportRollbackTest < Plastic::TestCase
  ImportRollback = Plastic::Graph::Knowledge::Legacy::ImportRollback

  # A file system that refuses to move the saved copy back.
  class BlockedRecovery < Plastic::Graph::FileSystem
    def initialize(root)
      super()
      @root = root
    end

    def rename(from, to)
      raise Errno::EACCES, "recovery blocked" if to == @root

      super
    end
  end

  def setup
    super
    folder.write("INDEX.md", "original")
  end

  def test_a_failed_import_puts_the_original_tree_back
    assert_raises(RuntimeError) { ImportRollback.new(folder.root).call { damage } }

    assert_equal "original", folder.read("INDEX.md")
  end

  def test_a_recovered_import_leaves_no_saved_copy_behind
    assert_raises(RuntimeError) { ImportRollback.new(folder.root).call { damage } }

    assert_empty snapshots
  end

  def test_a_failed_recovery_keeps_the_saved_copy_and_names_its_path
    rollback = ImportRollback.new(folder.root, files: BlockedRecovery.new(folder.root))

    error = assert_raises(Plastic::Invalid) { rollback.call { damage } }
    original = saved_index

    assert_equal "original", File.binread(original)
    assert_includes error.message, File.dirname(original)
  end

  def test_an_import_that_removed_the_store_gets_the_original_back
    assert_raises(RuntimeError) { ImportRollback.new(folder.root).call { remove_store } }

    assert_equal "original", folder.read("INDEX.md")
  end

  def test_a_passing_import_keeps_its_changes_and_no_saved_copy
    ImportRollback.new(folder.root).call { folder.write("INDEX.md", "imported") }

    assert_equal ["imported", []], [folder.read("INDEX.md"), snapshots]
  end

  private

  def snapshots = Dir.glob(File.join(File.dirname(folder.root), ".plastic-import-*"))

  def saved_index = File.join(snapshots.fetch(0), "global", "INDEX.md")

  def damage
    folder.write("INDEX.md", "changed by failed import")
    raise "import failed"
  end

  def remove_store
    FileUtils.rm_rf(folder.root)
    raise "import failed"
  end
end
