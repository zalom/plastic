# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../scripts/lib/plastic/graph/knowledge/archive/snapshot"

class KnowledgeArchiveSnapshotTest < Plastic::TestCase
  TreeError = Plastic::Graph::Knowledge::Archive::Tree::Error

  def setup
    super
    @intent = open_intent("Snapshot", status: "future")
    @database = store_graphs.databases.fetch(:work)
    @snapshot = Plastic::Graph::Knowledge::Archive::Snapshot.new(@database, @intent.intent_id, origin)
    @root = folder.path(@intent.dir)
    @entries = Plastic::Graph::Knowledge::Archive::Tree.read(@root)
  end

  def test_restoring_over_a_different_tree_refuses_and_keeps_it
    save(@entries)
    File.binwrite(File.join(@root, @intent.file), "changed after capture")

    error = assert_raises(TreeError) { @snapshot.restore(@root) }

    assert_equal "#{@root} differs from the archive; move it aside before restoring", error.message
  end

  def test_a_time_the_disk_cannot_hold_fails_verification_and_leaves_no_stage
    save(@entries.map { |entry| (entry[:kind] == "file") ? entry.merge(mtime: "1/3") : entry })
    FileUtils.remove_entry(@root)

    error = assert_raises(TreeError) { @snapshot.restore(@root) }

    assert_equal ["archive snapshot verification failed", []], [error.message, stages]
  end

  private

  def save(entries) = @database.transaction { |batch| @snapshot.capture(batch, entries) }

  def stages = Dir.glob(File.join(File.dirname(@root), ".plastic-archive-*"))
end
