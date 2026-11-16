# frozen_string_literal: true

require_relative "../../../test_helper"

class GraphBackupWriterTest < Plastic::TestCase
  include BackupHomes

  Backup = Plastic::Graph::Backup

  def failing_backup(home)
    Plastic::Graph::Database::ConnectionPool.release(File.join(home, "stores", "alpha"))
    File.write(store_file(home, "work_graph"), "not a database")
    assert_raises(StandardError) { backup_at(home, at(2026, 1, 1, 10, 0, 0)) }
  end

  def test_a_failed_copy_leaves_no_row
    home = fresh_home
    failing_backup(home)

    assert_empty row_names(home)
  end

  def test_a_failed_copy_marks_the_folder_failed
    home = fresh_home
    now = at(2026, 1, 1, 10, 0, 0)
    copy = Backup::Copy.new(now:, copier: ->(_source, _target) { raise StandardError, "disk is full" })

    assert_raises(StandardError) { Backup::Writer.new(File.join(home, "stores", "alpha"), "alpha", now:, copy:).call }
    assert_equal "failed", Backup::Folders.new(File.join(home, "stores", "alpha")).status("20260101100000")
  end

  def test_a_mode_key_the_writer_does_not_know_is_refused
    error = assert_raises(ArgumentError) { Backup::Writer.new(File.join(fresh_home, "stores", "alpha"), "alpha", now: at(2026, 1, 1, 10, 0, 0), speed: :fast) }

    assert_includes error.message, "speed"
  end

  def test_a_damaged_database_leaves_no_folder
    home = fresh_home
    failing_backup(home)

    assert_empty folder_names(home)
  end

  def test_a_finished_backup_is_marked_done_with_its_goal
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0), databases: %w[work_graph])
    folders = Backup::Folders.new(File.join(home, "stores", "alpha"))

    assert_equal ["done", "partial:work_graph.db"], [folders.status("20260101100000"), folders.goal("20260101100000")]
  end

  def test_a_full_backup_has_the_goal_full
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))

    assert_equal "full", Backup::Folders.new(File.join(home, "stores", "alpha")).goal("20260101100000")
  end

  def test_a_folder_without_a_status_file_is_unknown
    home = fresh_home
    FileUtils.mkdir_p(File.join(backups_dir(home), "20260101100000"))

    assert_equal "unknown", Backup::Folders.new(File.join(home, "stores", "alpha")).status("20260101100000")
  end

  def test_a_failed_row_insert_removes_the_folder
    home = fresh_home
    refusing = Object.new
    def refusing.transaction = raise(StandardError, "the row cannot be written")
    target = Backup::Target.new(refusing, File.join(home, "stores", "alpha"), "alpha", nil)
    publisher = Backup::Publisher.new(target, now: at(2026, 1, 1, 10, 0, 0))

    assert_raises(StandardError) { publisher.call }
    assert_empty folder_names(home)
  end

  def test_the_row_counts_the_databases_and_digests_the_sorted_names_and_digests
    home = fresh_home
    row = backup_at(home, at(2026, 1, 1, 10, 0, 0))
    folders = Backup::Folders.new(File.join(home, "stores", "alpha"))

    assert_equal [3, "alpha/20260101100000", folders.digest("20260101100000")], row.values_at(:files, :name, :sha256)
    assert_equal row.fetch(:bytes), folders.bytes("20260101100000")
  end

  def test_a_store_with_no_database_has_nothing_to_back_up
    writer = Backup::Writer.new(Dir.mktmpdir, "alpha", now: at(2026, 1, 1, 10, 0, 0))

    assert_raises(Backup::Writer::Error) { writer.call }
  end
end

class GraphBackupWriterLogTest < Plastic::TestCase
  include BackupHomes

  Backup = Plastic::Graph::Backup
  STAMP = "20260101100000"
  TIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z /

  def writer(home, copier: Backup::Copy.method(:vacuum), live: ->(_line) {}, databases: nil)
    Backup::Writer.new(File.join(home, "stores", "alpha"), "alpha", now: at(2026, 1, 1, 10, 0, 0), copy: Backup::Copy.new(now: at(2026, 1, 1, 10, 0, 0), databases:, copier:, live:))
  end

  def log_path(home) = File.join(backups_dir(home), STAMP, "backup.log")

  def log_lines(home) = File.readlines(log_path(home), chomp: true)

  def broken = ->(_source, _target) { raise StandardError, "disk is full" }

  def test_the_log_has_one_line_per_database_then_a_success_line_each_starting_with_a_utc_time
    home = fresh_home
    writer(home).call
    lines = log_lines(home)

    assert_equal 4, lines.size
    assert(lines.all? { |line| line.match?(TIME) })
  end

  def test_each_database_line_holds_its_name_size_and_result
    home = fresh_home
    writer(home).call
    copied = File.join(backups_dir(home), STAMP, "work_graph-#{STAMP}.db")
    line = log_lines(home).find { |text| text.include?("work_graph") }

    assert_includes line, "bytes=#{File.size(copied)}"
    assert_includes line, "result=ok"
  end

  def test_the_last_line_reports_success
    home = fresh_home
    writer(home).call

    assert_match(/backup result=done/, log_lines(home).last)
  end

  def test_a_failing_copy_ends_the_log_with_a_failure_line_holding_the_reason
    home = fresh_home

    assert_raises(StandardError) { writer(home, copier: broken).call }
    assert_match(/backup result=failed reason=disk is full/, log_lines(home).last)
  end

  def test_a_failing_copy_still_marks_the_folder_error
    home = fresh_home

    assert_raises(StandardError) { writer(home, copier: broken).call }
    assert_equal "failed", Backup::Folders.new(File.join(home, "stores", "alpha")).status(STAMP)
  end

  def test_the_first_database_line_is_in_the_file_before_the_second_copy_starts
    home = fresh_home
    seen = []
    copier = lambda do |source, target|
      seen << (File.exist?(log_path(home)) ? log_lines(home).size : 0)
      Backup::Copy.vacuum(source, target)
    end
    writer(home, copier:).call

    assert_equal [0, 1, 2], seen
  end

  def test_the_live_sink_receives_each_line_as_it_is_written
    home = fresh_home
    live = []
    writer(home, live: live.method(:push)).call

    assert_equal log_lines(home), live
  end

  def test_the_log_is_not_counted_as_a_database
    home = fresh_home

    assert_equal 3, writer(home).call.fetch(:files)
  end
end

class GraphBackupWriterSafetyTest < Plastic::TestCase
  include BackupHomes

  Backup = Plastic::Graph::Backup

  def root(home) = File.join(home, "stores", "alpha")

  def writer(home, time, **options) = Backup::Writer.new(root(home), "alpha", now: time, **options)

  def stamp_versions(home, version)
    Plastic::Graph::Database::ConnectionPool.release(root(home))
    %w[work_graph knowledge_graph references].each do |name|
      SQLite3::Database.new(store_file(home, name)).tap { |db| db.execute("PRAGMA user_version = #{version}") }.close
    end
  end

  def damage(home, name)
    Plastic::Graph::Database::ConnectionPool.release(root(home))
    File.binwrite(store_file(home, name), File.binread(store_file(home, name)).tap { |bytes| bytes[100, 200] = ("\xFF" * 200).b })
  end

  def test_a_database_that_fails_the_quick_check_stops_the_backup_before_any_copy
    home = fresh_home
    damage(home, "knowledge_graph")

    assert_raises(Backup::Writer::Error) { writer(home, at(2026, 1, 1, 10, 0, 0)).call }
    assert_empty folder_names(home)
  end

  def test_the_status_file_records_the_lowest_schema_version_of_the_store
    home = fresh_home
    stamp_versions(home, 3)
    writer(home, at(2026, 1, 1, 10, 0, 0)).call

    assert_equal 3, Backup::Folders.new(root(home)).report("20260101100000").fetch("version")
  end

  def test_an_automatic_backup_of_an_unchanged_store_is_skipped
    home = fresh_home
    writer(home, at(2026, 1, 1, 10, 0, 0), automatic: true).call

    assert_nil writer(home, at(2026, 1, 1, 23, 0, 0), automatic: true).call
    assert_equal ["20260101100000"], folder_names(home)
  end

  def test_an_automatic_backup_of_a_changed_store_is_written
    home = fresh_home
    writer(home, at(2026, 1, 1, 10, 0, 0), automatic: true).call
    add_intent(home)

    assert_kind_of Hash, writer(home, at(2026, 1, 1, 23, 0, 0), automatic: true).call
    assert_equal 2, folder_names(home).size
  end

  def test_a_manual_backup_of_an_unchanged_store_is_still_written
    home = fresh_home
    writer(home, at(2026, 1, 1, 10, 0, 0)).call
    writer(home, at(2026, 1, 1, 23, 0, 0)).call

    assert_equal 2, folder_names(home).size
  end

  def test_two_automatic_writers_starting_in_the_same_second_make_one_folder
    home = fresh_home
    FileUtils.mkdir_p(File.join(backups_dir(home), "20260101100000"))

    assert_nil writer(home, at(2026, 1, 1, 10, 0, 0), automatic: true).call
    assert_equal ["20260101100000"], folder_names(home)
  end

  def test_a_migration_backup_says_so_in_its_status_file
    home = fresh_home
    writer(home, at(2026, 1, 1, 10, 0, 0), reason: "migration").call

    assert_equal "migration", Backup::Folders.new(root(home)).report("20260101100000").fetch("reason")
  end
end
