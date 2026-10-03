# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../test_helpers/method_replacement"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/writer"

class KnowledgeArchiveRecoveryTest < Plastic::TestCase
  include MethodReplacement

  def setup
    super
    @intent = open_intent("Recovery", status: "future")
    @graphs = store_graphs
    @database = @graphs.databases.fetch(:work)
    @writer = Plastic::Graph::Knowledge::Archive::Writer.new(@graphs.databases, @graphs.retrieval, folder, session: "archive-test")
    @root = folder.path(@intent.dir)
  end

  def test_capture_failure_never_removes_the_source
    with_replacement(@database, :transaction, ->(*) { raise Plastic::Graph::Database::Error, "disk full" }) do
      assert_raises(Plastic::Graph::Database::Error) { @writer.archive(@intent.intent_id) }
    end

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

    with_replacement(File, :rename, ->(*) { raise Errno::EACCES, "rename blocked" }) do
      refute @writer.restore(@intent.intent_id).first
    end
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
    with_replacement(@writer, :remove_printed, ->(*) { raise Plastic::Graph::Database::Error, "disk full" }) do
      assert_raises(Plastic::Graph::Database::Error) { @writer.archive(@intent.intent_id) }
    end
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

  def archive_successfully
    assert @writer.archive(@intent.intent_id).first
  end

  def check_failed_publication
    assert retrieval.archived?(@intent.intent_id)
    refute_path_exists @root
    assert_empty Dir.glob(File.join(File.dirname(@root), ".plastic-archive-*"))
  end

  def fail_marker
    with_replacement(@database, :transaction, ->(*) { raise Plastic::Graph::Database::Error, "disk full" }) do
      assert_raises(Plastic::Graph::Database::Error) { @writer.restore(@intent.intent_id) }
    end
    assert retrieval.archived?(@intent.intent_id)
  end

  def interrupt_removal
    with_replacement(FileUtils, :remove_entry, ->(*) { raise Errno::EACCES, "remove blocked" }) do
      refute @writer.archive(@intent.intent_id).first
    end
    assert retrieval.archived?(@intent.intent_id)
    assert File.directory?(@root)
  end
end
