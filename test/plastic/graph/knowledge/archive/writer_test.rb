# frozen_string_literal: true

require "delegate"
require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchiveWriterTest < Plastic::TestCase
  # A database whose transactions fail, as on a full disk.
  class FullDisk < SimpleDelegator
    def transaction(*) = raise(Plastic::Graph::Database::Error, "disk full")
  end

  # A database whose printed-file records cannot be cleared.
  class StuckPrinted < SimpleDelegator
    def transaction(*) = super { |batch| yield StuckBatch.new(batch) }
  end

  # A batch that fails on removing printed-file records.
  class StuckBatch < SimpleDelegator
    def remove_all(table, *)
      raise Plastic::Graph::Database::Error, "disk full" if table == :printed

      super
    end
  end

  # A file system that refuses to rename.
  class BlockedRename < Plastic::Graph::FileSystem
    def rename(*) = raise(Errno::EACCES, "rename blocked")
  end

  # A file system that refuses to remove.
  class BlockedRemoval < Plastic::Graph::FileSystem
    def remove_entry(*) = raise(Errno::EACCES, "remove blocked")
  end

  def setup
    super
    @intent = open_intent("Recovery", status: "future")
    @graphs = store_graphs
    @writer = writer
    @root = folder.path(@intent.dir)
  end

  def test_capture_failure_never_removes_the_source
    assert_raises(Plastic::Graph::Database::Error) { writer(databases: full_disk).archive(@intent.intent_id) }

    assert File.directory?(@root)
    refute retrieval.archived?(@intent.intent_id)
  end

  def test_deletion_failure_leaves_snapshot_and_retry_finishes
    interrupt_removal
    File.unlink(File.join(@root, @intent.file))
    archive_successfully

    refute_path_exists @root
    assert @writer.restore(@intent.intent_id).first
    assert File.file?(File.join(@root, @intent.file))
  end

  def test_deletion_retry_preserves_new_or_changed_files
    interrupt_removal
    File.binwrite(File.join(@root, @intent.file), "owner edit after capture")

    refute @writer.archive(@intent.intent_id).first
    assert_equal "owner edit after capture", File.binread(File.join(@root, @intent.file))
    assert retrieval.archived?(@intent.intent_id)
  end

  def test_publication_failure_keeps_archive_and_cleans_staging
    archive_successfully

    refute writer(files: BlockedRename.new).restore(@intent.intent_id).first
    check_failed_publication

    assert @writer.restore(@intent.intent_id).first
  end

  def test_marker_failure_after_publication_can_retry_without_rewriting
    archive_successfully
    fail_marker
    inode = File.stat(@root).ino

    assert @writer.restore(@intent.intent_id).first
    assert_equal inode, File.stat(@root).ino
    refute retrieval.archived?(@intent.intent_id)
  end

  def test_cleanup_failure_after_removal_can_retry
    assert_raises(Plastic::Graph::Database::Error) { writer(databases: stuck_printed).archive(@intent.intent_id) }
    archive_successfully

    refute_path_exists @root
    assert retrieval.archived?(@intent.intent_id)
  end

  def test_deletion_retry_preserves_changed_file_time
    interrupt_removal
    path = File.join(@root, @intent.file)
    File.utime(Time.at(1234), Time.at(1234), path)

    refute @writer.archive(@intent.intent_id).first
    assert_equal Time.at(1234), File.mtime(path)
  end

  private

  def writer(databases: @graphs.databases, **collaborators)
    Plastic::Graph::Knowledge::Archive::Writer.new(databases, @graphs.retrieval, folder, session: "archive-test", **collaborators)
  end

  def full_disk = @graphs.databases.merge(work: FullDisk.new(@graphs.databases.fetch(:work)))

  def stuck_printed = @graphs.databases.merge(references: StuckPrinted.new(@graphs.databases.fetch(:references)))

  def archive_successfully
    assert @writer.archive(@intent.intent_id).first
  end

  def check_failed_publication
    assert retrieval.archived?(@intent.intent_id)
    refute_path_exists @root
    assert_empty Dir.glob(File.join(File.dirname(@root), ".plastic-archive-*"))
  end

  def fail_marker
    assert_raises(Plastic::Graph::Database::Error) { writer(databases: full_disk).restore(@intent.intent_id) }
    assert retrieval.archived?(@intent.intent_id)
  end

  def interrupt_removal
    refute writer(files: BlockedRemoval.new).archive(@intent.intent_id).first
    assert retrieval.archived?(@intent.intent_id)
    assert File.directory?(@root)
  end
end
