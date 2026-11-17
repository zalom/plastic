# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphBackupRestorerTest < Plastic::TestCase
  include BackupHomes

  Restorer = Plastic::Graph::Backup::Restorer
  STAMP = "20260101100000"

  def setup
    super
    @restore_home = fresh_home
    backup_at(@restore_home, at(2026, 1, 1, 10, 0, 0))
    add_intent(@restore_home)
  end

  def root = File.join(@restore_home, "stores", "alpha")

  def local_db = Plastic::Graph.create(home: @restore_home, store: "alpha").databases.fetch(:local)

  def restorer(now: at(2026, 6, 1, 12, 0, 0)) = Restorer.new(Plastic::Graph::Backup::Target.new(local_db, root, "alpha", nil), Plastic::Graph.open(home: @restore_home, store: "alpha").retrieval, now:)

  def lock_intent(renewed_at)
    local_db.transaction do |batch|
      batch.put(:locks, { store: "alpha", intent_id: 1, session_id: "s-1", mode: "auto", locked_at: renewed_at, renewed_at: }, statement: :insert)
    end
  end

  def bytes(name) = File.binread(store_file(@restore_home, name))

  def test_a_fresh_delivery_lock_refuses_the_restore
    lock_intent(at(2026, 6, 1, 11, 50, 0).iso8601)
    before = bytes("work_graph")

    assert_raises(Restorer::Locked) { restorer.call(STAMP) }
    assert_equal before, bytes("work_graph")
  end

  def test_a_lapsed_delivery_lock_does_not_refuse_the_restore
    lock_intent(at(2026, 6, 1, 9, 0, 0).iso8601)
    restorer.call(STAMP)

    assert_equal 1, intent_count(@restore_home)
  end

  def test_a_lapsed_delivery_lock_held_by_an_open_node_refuses_the_restore
    lock_intent(at(2026, 6, 1, 9, 0, 0).iso8601)
    Plastic::Graph.open(home: @restore_home, store: "alpha").databases.fetch(:work).transaction do |batch|
      batch.put(:nodes, { intent_id: "1", id: "n1", state: "claimed", by: "s-1", updated_at: at(2026, 6, 1, 11, 0, 0).iso8601 })
    end

    assert_raises(Restorer::Locked) { restorer.call(STAMP) }
  end

  def test_a_restore_first_backs_up_the_current_databases
    restorer.call(STAMP)

    assert_equal [STAMP, "20260601120000"], folder_names(@restore_home)
  end

  def test_a_file_that_fails_the_check_replaces_nothing
    File.write(Dir.glob(File.join(backups_dir(@restore_home), STAMP, "work_graph-*.db")).first, "not a database")
    before = bytes("work_graph")

    assert_raises(Restorer::Rejected) { restorer.call(STAMP) }
    assert_equal before, bytes("work_graph")
  end

  def test_a_file_with_the_wrong_schema_stamp_replaces_nothing
    path = Dir.glob(File.join(backups_dir(@restore_home), STAMP, "work_graph-*.db")).first
    File.delete(path)
    SQLite3::Database.new(path).tap { |db| db.execute("CREATE TABLE other (id INTEGER)") }.close
    before = bytes("work_graph")

    assert_raises(Restorer::Rejected) { restorer.call(STAMP) }
    assert_equal before, bytes("work_graph")
  end

  def test_stale_journal_files_beside_a_target_are_removed
    %w[-journal -wal -shm].each { |suffix| File.write("#{store_file(@restore_home, "work_graph")}#{suffix}", "stale") }
    restorer.call(STAMP)

    assert_empty Dir.glob(File.join(root, "work_graph.db-*"))
  end

  def test_a_failed_second_rename_puts_the_first_database_back
    before = bytes("knowledge_graph")
    FileUtils.mkdir_p(File.join(root, "references.db.old", "keep"))

    assert_raises(SystemCallError) { restorer.call(STAMP) }
    assert_equal before, bytes("knowledge_graph")
    assert_equal 2, intent_count(@restore_home)
  end

  def mark(status) = Plastic::Graph::Backup::Folders.new(root).write_report(STAMP, status:, goal: "full")

  def test_a_backup_that_is_not_done_is_refused_naming_its_status
    mark("in-progress")
    error = assert_raises(Restorer::NotDone) { restorer.call(STAMP) }

    assert_includes error.message, "in-progress"
  end

  def test_a_backup_marked_failed_replaces_nothing
    mark("failed")
    before = bytes("work_graph")

    assert_raises(Restorer::NotDone) { restorer.call(STAMP) }
    assert_equal before, bytes("work_graph")
  end

  def test_a_restore_of_a_listed_database_replaces_only_that_database
    before = bytes("knowledge_graph")
    restorer.call(STAMP, databases: %w[work_graph])

    assert_equal [1, before], [intent_count(@restore_home), bytes("knowledge_graph")]
  end

  def test_a_database_the_backup_does_not_hold_is_refused
    backup_at(@restore_home, at(2026, 2, 1, 10, 0, 0), databases: %w[work_graph])

    assert_raises(Restorer::Missing) { restorer.call("20260201100000", databases: %w[references]) }
  end

  def test_the_status_file_is_never_copied_into_the_store
    restorer.call(STAMP)

    refute_includes Dir.children(root), "status.yml"
  end

  def test_a_restore_closes_the_open_connections_of_the_store
    intent_count(@restore_home)
    restorer.call(STAMP)

    refute_includes Plastic::Graph::Database::ConnectionPool.connections.keys, store_file(@restore_home, "work_graph")
  end
end

# A second migration that adds a table, standing in for the next release: a backup restores at its own version and migrates forward.
class GraphBackupRestoreForwardTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  Restorer = Plastic::Graph::Backup::Restorer
  Sequences = Plastic::Graph::SchemaSequences
  Store1 = Plastic::Graph::SchemaStore1
  STAMP = "20260101100000"

  def setup
    super
    @home = fresh_home
    backup_at(@home, at(2026, 1, 1, 10, 0, 0))
    tables = Store1::TABLES.merge("work_graph" => Store1::TABLES.fetch("work_graph") + ["extra"])
    second = Sequences::Migration.new(2, ->(connection, key) { connection.execute("CREATE TABLE extra (a)") if key == :work }, tables)
    @sequences = { home: Sequences::SEQUENCES.fetch(:home), store: [*Sequences::SEQUENCES.fetch(:store), second] }
  end

  def root = File.join(@home, "stores", "alpha")

  # The store databases stand at version 2, which the gate of this code refuses, so the restorer gets the local database and a retrieval that only names the store.
  def restorer
    target = Plastic::Graph::Backup::Target.new(Plastic::Graph::Database.open_local(@home).fetch(:local), root, "alpha", nil)
    Restorer.new(target, Struct.new(:store).new("alpha"), now: at(2026, 6, 1, 12, 0, 0), sequences: @sequences)
  end

  def store_paths = Dir.glob(File.join(root, "*.db")).sort

  def migrate_store
    store_paths.each do |path|
      key = Plastic::Graph::Schema.store.find { |candidate| Plastic::Graph::Schema.file(candidate) == File.basename(path) }
      db = SQLite3::Database.new(path)
      Sequences.migrate(db, @sequences.fetch(:store), key)
      db.close
    end
  end

  def digests = store_paths.to_h { |path| [File.basename(path), row_digest(path)] }

  def store_versions = user_versions(@home).select { |path, _| path.include?("/alpha/") }.values.uniq

  def test_a_backup_at_version_one_restores_after_the_store_moved_to_two_and_migrates_forward_to_equal_rows
    migrate_store
    migrated = digests
    restorer.call(STAMP)

    assert_equal [1], store_versions
    migrate_store

    assert_equal [migrated, [2]], [digests, store_versions]
  end

  def test_a_restore_of_one_database_across_a_version_boundary_is_refused_and_names_the_whole_store_restore
    migrate_store
    before = File.binread(File.join(root, "work_graph.db"))
    error = assert_raises(Restorer::VersionMismatch) { restorer.call(STAMP, databases: %w[work_graph]) }

    assert_includes error.message, "restore the whole store"
    assert_equal before, File.binread(File.join(root, "work_graph.db"))
  end

  def test_the_refusal_for_a_listed_database_across_a_version_boundary_is_given_before_the_restore
    migrate_store

    assert_includes restorer.refusal(STAMP, databases: %w[work_graph]), "restore the whole store"
  end

  def test_a_backup_recording_a_version_above_the_code_is_rejected
    Plastic::Graph::Backup::Folders.new(root).write_report(STAMP, status: "done", goal: "full", version: 9)
    error = assert_raises(Restorer::Rejected) { restorer.call(STAMP) }

    assert_includes error.message, "newer than this code"
  end
end
