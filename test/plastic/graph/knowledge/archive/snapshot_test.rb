# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/archive/snapshot"

class KnowledgeArchiveSnapshotTest < Plastic::TestCase
  TreeError = Plastic::Graph::Knowledge::Archive::Tree::Error

  def setup
    super
    @intent = open_intent("Snapshot", status: "future")
    @database = store_graphs.databases.fetch(:store)
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

  def test_restoring_over_no_tree_publishes_the_saved_one_and_leaves_no_stage
    save(@entries)
    FileUtils.remove_entry(@root)
    @snapshot.restore(@root)

    assert_equal [@entries, []], [Plastic::Graph::Knowledge::Archive::Tree.read(@root), stages]
  end

  def test_restoring_an_intent_with_no_snapshot_refuses
    error = assert_raises(TreeError) { @snapshot.restore(@root) }

    assert_equal "intent #{@intent.intent_id} has no archive snapshot", error.message
  end

  class Racing < Plastic::Graph::FileSystem
    def present?(_path) = true
  end

  def test_a_root_that_appears_during_restoration_is_preserved_and_no_stage_stays
    save(@entries)
    FileUtils.remove_entry(@root)
    racing = Plastic::Graph::Knowledge::Archive::Snapshot.new(@database, @intent.intent_id, origin, files: Racing.new)
    error = assert_raises(TreeError) { racing.restore(@root) }

    assert_equal ["#{@root} appeared during restoration; preserved", false, []], [error.message, File.exist?(@root), stages]
  end

  private

  def save(entries) = @database.transaction { |batch| @snapshot.capture(batch, entries) }

  def stages = Dir.glob(File.join(File.dirname(@root), ".plastic-archive-*"))
end
