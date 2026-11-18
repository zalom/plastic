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

  def claim_node(at)
    graphs = Plastic::Graph.open(home: @restore_home, store: "alpha", session: "s-1", clock: Struct.new(:now).new(at))
    graphs.work.add_node(intent_id: "1", title: "Build")
    graphs.work.claim_node(intent_id: "1", id: "n1", by: "s-1")
  end

  def bytes(name) = File.binread(store_file(@restore_home, name))

  def test_a_live_claim_refuses_the_restore
    claim_node(at(2026, 6, 1, 11, 50, 0))
    before = bytes("work_graph")

    assert_raises(Restorer::Claimed) { restorer.call(STAMP) }
    assert_equal before, bytes("work_graph")
  end

  def test_a_lapsed_claim_does_not_refuse_the_restore
    claim_node(at(2026, 6, 1, 9, 0, 0))
    restorer.call(STAMP)

    assert_equal 1, intent_count(@restore_home)
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
    before = bytes("work_graph")
    FileUtils.mkdir_p(File.join(root, "knowledge_graph.db.old", "keep"))

    assert_raises(SystemCallError) { restorer.call(STAMP) }
    assert_equal before, bytes("work_graph")
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
    before = bytes("work_graph")
    restorer.call(STAMP, databases: %w[knowledge_graph])

    assert_equal [1, before], [intent_count(@restore_home), bytes("work_graph")]
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

  def test_a_restore_ends_with_the_rebuild_of_the_retrieval_index
    open_store.work.print_intent("1")
    backup_at(@restore_home, at(2026, 2, 1, 10, 0, 0))
    open_store.databases.fetch(:store).transaction { |batch| batch.add("DELETE FROM document_passages") }
    store_backups.restore("20260201100000")
    store_backups.rebuild_index

    assert_operator passage_count, :>, 0
  end

  def open_store = Plastic::Graph.open(home: @restore_home, store: "alpha")

  def store_backups = Plastic::Graph::Backup::StoreBackups.new(local_db, root, open_store.retrieval, clock: Struct.new(:now).new(at(2026, 6, 1, 12, 0, 0)))

  def passage_count = open_store.databases.fetch(:store).row("SELECT count(*) AS n FROM document_passages").fetch("n")
end

# A store that moved above the version of a backup: the whole store restores to the backup's version, and one database alone is refused.
class GraphBackupRestoreForwardTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  Restorer = Plastic::Graph::Backup::Restorer
  STAMP = "20260101100000"

  def setup
    super
    @home = fresh_home
    backup_at(@home, at(2026, 1, 1, 10, 0, 0))
  end

  def root = File.join(@home, "stores", "alpha")

  # The store databases stand above the newest version, which the gate of this code refuses, so the restorer gets the local database and a retrieval that only names the store.
  def restorer
    target = Plastic::Graph::Backup::Target.new(Plastic::Graph::Database.open_local(@home).fetch(:local), root, "alpha", nil)
    Restorer.new(target, Struct.new(:store, :claimed_nodes).new("alpha", []), now: at(2026, 6, 1, 12, 0, 0))
  end

  def store_paths = Dir.glob(File.join(root, "{work_graph,knowledge_graph}.db")).sort

  def move_above
    Plastic::Graph::Database::ConnectionPool.release(root)
    record_unknown_version(File.join(root, "knowledge_graph.db"))
  end

  def store_versions = [recorded_versions(File.join(root, "knowledge_graph.db"))]

  def test_a_whole_store_restore_after_the_store_moved_above_brings_every_database_to_the_backup_version
    move_above
    restorer.call(STAMP)

    assert_equal [Plastic::Graph::MIGRATIONS.versions(:store)], store_versions
  end

  def test_a_restore_of_one_database_across_a_version_boundary_is_refused_and_names_the_whole_store_restore
    move_above
    before = File.binread(File.join(root, "work_graph.db"))
    error = assert_raises(Restorer::VersionMismatch) { restorer.call(STAMP, databases: %w[work_graph]) }

    assert_includes error.message, "restore the whole store"
    assert_equal before, File.binread(File.join(root, "work_graph.db"))
  end

  def test_the_refusal_for_a_listed_database_across_a_version_boundary_is_given_before_the_restore
    move_above

    assert_includes restorer.refusal(STAMP, databases: %w[work_graph]), "restore the whole store"
  end

  def test_a_backup_recording_a_version_above_the_code_is_rejected
    Plastic::Graph::Backup::Folders.new(root).write_report(STAMP, status: "done", goal: "full", version: SchemaVersions::UNKNOWN.to_i)
    error = assert_raises(Restorer::Rejected) { restorer.call(STAMP) }

    assert_includes error.message, "newer than this code"
  end
end

# A restore of listed databases is judged against the live knowledge database, and a store with none has nothing to disagree with.
class GraphBackupRestorerLiveVersionTest < Plastic::TestCase
  include BackupHomes

  STAMP = "20260101100000"

  def test_a_listed_database_is_not_refused_when_the_store_holds_no_knowledge_database
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    target = Plastic::Graph::Backup::Target.new(Plastic::Graph.create(home:, store: "alpha").databases.fetch(:local), File.join(home, "stores", "alpha"), "alpha", nil)
    restorer = Plastic::Graph::Backup::Restorer.new(target, Plastic::Graph.open(home:, store: "alpha").retrieval, now: at(2026, 6, 1, 12, 0, 0))
    File.delete(store_file(home, "knowledge_graph"))

    assert_nil restorer.refusal(STAMP, databases: %w[work_graph])
  end
end
