# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseArchiveEntryTest < Minitest::Test
  include ReleaseHelper

  def test_a_plain_file_keeps_its_name_and_counts_its_bytes
    entry = entry_of { |tar| tar.add_file_simple("package/VERSION", 0o644, 6) { |io| io.write("2.0.3\n") } }

    assert_equal ["package/VERSION", 6], [entry.checked_name, entry.content_bytes]
  end

  def test_a_directory_counts_no_bytes
    entry = entry_of { |tar| tar.mkdir("package", 0o755) }

    assert_equal 0, entry.content_bytes
  end

  def test_a_link_is_refused
    entry = entry_of { |tar| tar.add_symlink("package/link", "/etc/passwd", 0o777) }

    error = assert_raises(InstallerRelease::ArchiveError) { entry.checked_name }
    assert_equal "archive contains link package/link", error.message
  end

  def test_a_name_that_climbs_out_of_staging_is_refused
    entry = entry_of { |tar| tar.add_file_simple("package/../../evil", 0o644, 0) { nil } }

    error = assert_raises(InstallerRelease::ArchiveError) { entry.checked_name }
    assert_equal "archive path escapes staging", error.message
  end

  def test_an_absolute_name_is_refused
    entry = entry_of { |tar| tar.add_file_simple("/evil", 0o644, 0) { nil } }

    error = assert_raises(InstallerRelease::ArchiveError) { entry.checked_name }
    assert_equal "archive path is unsafe", error.message
  end

  def test_write_under_puts_a_file_below_the_root
    root = written { |tar| tar.add_file_simple("package/VERSION", 0o644, 6) { |io| io.write("2.0.3\n") } }

    assert_equal "2.0.3\n", File.read(File.join(root, "package", "VERSION"))
  end

  def test_write_under_makes_a_directory_entry
    root = written { |tar| tar.mkdir("package/bin", 0o755) }

    assert File.directory?(File.join(root, "package", "bin"))
  end

  private

  def entry_of(&) = open_entry(tar_archive(&)) { |entry| entry }

  def written(&)
    root = File.join(@root, "out")
    open_entry(tar_archive(&)) { |entry| entry.write_under(root) }
    root
  end

  def open_entry(archive)
    Zlib::GzipReader.open(archive) { |gzip| yield InstallerRelease::ArchiveEntry.new(Gem::Package::TarReader.new(gzip).first) }
  end
end
