# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeBackupWriterLogTest < Plastic::TestCase
  include BackupHomes

  Backup = Plastic::Graph::Knowledge::Backup
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
