# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseArchiveTest < Minitest::Test
  include ReleaseHelper

  def test_lists_the_entries_of_a_release_archive
    assert_includes InstallerRelease::Archive.new(archive_with).entry_names, "package/bin/plastic"
  end

  def test_rejects_unsafe_paths_before_extraction
    assert_equal "archive path escapes staging", problem { |tar| file_entry(tar, "../escape", "x") }
    assert_equal "archive path is unsafe", problem { |tar| file_entry(tar, "/etc/escape", "x") }
  end

  def test_rejects_links_special_entries_and_duplicates
    assert_equal "archive contains link package/link", problem { |tar| tar.add_symlink("package/link", "/etc", 0o777) }
    assert_equal "archive contains special entry package/fifo", problem_in(special_archive("package/fifo"))
    assert_equal "archive contains duplicate entry a", problem { |tar| 2.times { tar.mkdir("a", 0o755) } }
  end

  def test_rejects_an_archive_over_its_limits
    tiny = InstallerRelease::Archive::Limits.new(bytes: 3, entries: 1)
    two_entries = tar_archive { |tar| %w[a b].each { |name| tar.mkdir(name, 0o755) } }
    large = tar_archive("large.tgz") { |tar| file_entry(tar, "a", "a" * 5000) }

    assert_equal "archive exceeds entry limit", problem_in(two_entries, InstallerRelease::Archive::Limits.new(bytes: 10_000, entries: 1))
    assert_equal "archive exceeds content limit", problem_in(large, InstallerRelease::Archive::Limits.new(bytes: 1000, entries: 5))
    assert_equal "archive exceeds byte limit", problem_in(large, tiny)
  end

  def test_rejects_an_archive_that_cannot_be_read
    path = File.join(@root, "broken.tgz")
    File.binwrite(path, "not gzip")

    assert_match(/archive cannot be read/, problem_in(path))
  end

  def test_refuses_to_write_an_entry_outside_the_staging_directory
    home_entry = tar_archive { |tar| file_entry(tar, "~/escape", "x") }

    error = assert_raises(InstallerRelease::ArchiveError) { InstallerRelease::Archive.new(home_entry).extract_to(@root) }
    assert_equal "archive path escapes staging", error.message
  end

  private

  def special_archive(name)
    header = Gem::Package::TarHeader.new(name: name, mode: 0o644, size: 0, typeflag: "6", prefix: "")
    header.update_checksum
    path = File.join(@root, "special.tgz")
    Zlib::GzipWriter.open(path) { |gzip| gzip.write(header.to_s + ("\0" * 1024)) }
    path
  end

  def file_entry(tar, name, body)
    tar.add_file_simple(name, 0o644, body.bytesize) { |file| file.write(body) }
  end

  def problem(&) = problem_in(tar_archive(&))

  def problem_in(path, limits = InstallerRelease::Archive::DEFAULT_LIMITS)
    error = assert_raises(InstallerRelease::ArchiveError) { InstallerRelease::Archive.new(path, limits: limits).entry_names }
    error.message
  end
end
