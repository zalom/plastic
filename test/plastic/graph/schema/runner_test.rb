# frozen_string_literal: true

require "digest"
require_relative "../../../test_helper"

class SchemaRunnerTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  Runner = Plastic::Graph::SchemaRunner
  Sequences = Plastic::Graph::SchemaSequences
  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  def run_runner(home, **options) = Runner.new(home:, now: NOW, **options).call

  def old_home = old_layout(fresh_home)

  def store_files(home, slug = "alpha") = Dir.glob(File.join(home, "stores", slug, "*.db")).sort

  def intent_status(home, slug)
    path = store_files(home, slug).find { |file| layout_of(file).any? { |_type, name, _sql| name == "intents" } }
    SQLite3::Database.new(path, readonly: true).get_first_value("SELECT status FROM intents WHERE intent_id = '7'")
  end

  def test_an_old_layout_home_migrated_through_every_migration_has_the_layout_of_a_new_database
    home = old_home
    run_runner(home)

    assert_equal layouts(fresh_home), layouts(home)
  end

  def test_every_database_is_stamped_with_the_newest_version_of_its_sequence
    home = old_home
    run_runner(home)
    versions = user_versions(home).transform_keys { |path| path.delete_prefix(home) }

    assert_equal [Sequences.newest(:home)], versions.slice("/plastic.db").values
    assert_equal [Sequences.newest(:store)], versions.except("/plastic.db").values.uniq
  end

  def test_the_old_word_for_work_under_way_becomes_in_progress
    home = old_home
    run_runner(home)

    assert_equal "in_progress", intent_status(home, "alpha")
  end

  def test_a_backup_of_the_store_is_taken_first_and_says_it_is_the_migration_backup
    home = old_home
    run_runner(home)
    report = Plastic::Graph::Backup::Folders.new(File.join(home, "stores", "alpha")).report(folder_names(home).first)

    assert_equal ["migration", 0, "done"], report.values_at("reason", "version", "status")
  end

  def test_a_fresh_backup_does_not_stop_the_runner_from_taking_its_own
    home = old_home
    Plastic::Graph::Backup::Writer.new(File.join(home, "stores", "alpha"), "alpha", now: NOW - 60).call
    run_runner(home)

    assert_equal 2, folder_names(home).size
  end

  def test_a_home_that_is_current_changes_no_byte_and_takes_no_backup
    home = old_home
    run_runner(home)
    before = file_bytes(home)
    count = folder_names(home).size
    run_runner(home)

    assert_equal [before, count], [file_bytes(home), folder_names(home).size]
  end

  def test_a_store_whose_backup_fails_stays_behind_and_the_other_store_migrates
    home = old_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    File.write(store_file(home, "work_graph"), "not a database")
    before = bytes_in(home, "/alpha/")
    report = run_runner(home)

    assert_equal [["alpha"], before], [report.failed.keys, bytes_in(home, "/alpha/")]
    assert_equal Sequences.newest(:store), user_versions(home).fetch(store_file(home, "work_graph", "beta"))
  end

  def test_a_store_whose_backup_folder_cannot_be_written_stays_behind
    home = old_home
    FileUtils.mkdir_p(File.join(home, "stores", "alpha", "backups"), mode: 0o555)
    bytes_in(home, "/alpha/")
    report = run_runner(home)

    assert_equal [["alpha"], [0]], [report.failed.keys, versions_in(home, "/alpha/")]
  end

  def test_a_run_that_is_killed_inside_a_migration_leaves_every_byte_of_the_file_as_it_was
    home = old_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    before = bytes_in(home, "/stores/")

    assert_raises(RuntimeError) { run_runner(home, sequences: killed_store_sequences) }
    Plastic::Graph::Database::ConnectionPool.release(home)

    assert_equal before, bytes_in(home, "/stores/")
    run_runner(home)

    assert_equal layouts(fresh_home), layouts(home)
  end

  def test_a_store_with_only_the_work_database_migrates_and_gains_no_other_file
    home = old_home
    Plastic::Graph::Database::ConnectionPool.release(home)
    (store_files(home) - [store_file(home, "work_graph")]).each { |path| File.delete(path) }
    run_runner(home)

    assert_equal [store_file(home, "work_graph")], store_files(home)
    assert_equal Sequences.newest(:store), user_versions(home).fetch(store_file(home, "work_graph"))
  end

  def test_backup_migrate_restore_and_migrate_again_give_equal_row_digests
    home = old_home
    run_runner(home)
    migrated = store_digests(home).except("retrieval_graph.db")
    Plastic::Graph::Database::ConnectionPool.release(home)
    restore_call(home, "--store", "alpha", "--latest")

    assert_equal [Sequences.newest(:store)], versions_in(home, "/alpha/")
    assert_equal migrated, store_digests(home).except("retrieval_graph.db")
  end

  def killed_store_sequences
    killed = Sequences::Migration.new(1, ->(connection, key) { connection.execute_batch(Plastic::Graph::Schema.fetch(key)).then { raise "killed" } }, {})
    { home: Sequences::SEQUENCES.fetch(:home), store: [killed] }
  end

  def bytes_in(home, part) = file_bytes(home).select { |path, _| path.include?(part) }

  def versions_in(home, part) = user_versions(home).select { |path, _| path.include?(part) }.values.uniq

  def store_digests(home) = store_files(home).to_h { |path| [File.basename(path), row_digest(path)] }
end
