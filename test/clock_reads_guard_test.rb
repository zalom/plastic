# frozen_string_literal: true

require_relative "test_helper"

class ClockReadsGuardTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)
  CLOCK_READ = /\bTime\.now\b|\bPlastic\.now\b/

  def lib_files = Dir.glob(File.join(LIB, "**", "*.rb"))

  def test_the_lib_files_are_read_from_the_disk
    refute_empty lib_files
  end

  def test_no_lib_file_reads_the_clock_by_name
    hits = lib_files.select { |path| File.read(path, encoding: "UTF-8").match?(CLOCK_READ) }

    assert_empty hits.map { |path| path.delete_prefix("#{LIB}/") }
  end

  def test_a_timestamp_is_written_from_the_time_it_is_given
    assert_equal "2026-10-05T10:00:00+02:00", Plastic.timestamp(Time.new(2026, 10, 5, 10, 0, 0, "+02:00"))
  end
end
