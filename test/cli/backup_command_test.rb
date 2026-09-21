# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "rubygems/package"
require "zlib"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"
require_relative "../../scripts/lib/backup"

class CliBackupCommandTest < Minitest::Test
  NAME = /plastic-backup--\d{8}T\d{6}Z\.tar\.gz/

  def setup
    @dir = Dir.mktmpdir("plastic-cli-backup")
    @fixture = CliFixture.new(@dir).global_store(active: [["1", "Alpha"]])
    File.write(File.join(home, "config.yml"), "channel: stable\n")
    File.write(File.join(home, "projects.yml"), "projects: []\n")
  end

  def teardown
    FileUtils.chmod(0o755, home)
    FileUtils.remove_entry(@dir)
  end

  def home
    @fixture.plastic_home
  end

  def plastic(*argv)
    [@fixture.out, @fixture.err].each do |io|
      io.truncate(0)
      io.rewind
    end
    Plastic::CLI.call(argv, directory: @dir, **@fixture.streams)
  end

  def archives
    Dir.glob(File.join(home, "backups", "*"))
  end

  def unpacked
    entries = {}
    Zlib::GzipReader.open(archives.first) do |gzip|
      Gem::Package::TarReader.new(gzip).each { |entry| entries[entry.full_name] = entry.read }
    end
    entries
  end

  def test_a_backup_makes_git_ignore_the_backups_directory
    plastic("sync")
    plastic("backup")

    assert_includes File.read(File.join(home, ".gitignore")).lines.map(&:strip), "backups/"
  end

  def test_backup_writes_one_archive_with_the_dated_name
    plastic("sync")

    assert_equal 0, plastic("backup")
    assert_equal 1, archives.size
    assert_match(/\A#{NAME}\z/o, File.basename(archives.first))
  end

  def test_the_archive_holds_the_three_databases_the_root_files_and_the_manifest
    plastic("sync")
    plastic("backup")

    assert_equal %w[INDEX.md config.yml knowledge_graph.db manifest.json projects.yml references.db work_graph.db], unpacked.keys.sort
  end

  def test_every_file_matches_its_manifest_entry
    plastic("sync")
    plastic("backup")
    files = unpacked
    listed = JSON.parse(files.delete("manifest.json"))["files"]

    assert_equal files.map { |name, body| [name, body.bytesize, Digest::SHA256.hexdigest(body)] }.sort,
      listed.map { |file| file.values_at("name", "bytes", "sha256") }.sort
  end

  def test_the_manifest_names_the_version_and_the_time
    plastic("sync")
    plastic("backup")
    manifest = JSON.parse(unpacked["manifest.json"])

    assert_match(/\A\d+\.\d+\.\d+/, manifest["version"])
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/, manifest["at"])
  end

  def test_a_database_in_the_archive_passes_the_integrity_check
    plastic("sync")
    plastic("backup")
    copy = File.join(@dir, "work_graph.db")
    File.binwrite(copy, unpacked["work_graph.db"])

    assert_equal [{"integrity_check" => "ok"}], Plastic::Sqlite.call(copy, "PRAGMA integrity_check;")
  end

  def test_backup_prints_the_archive_and_the_restore_as_the_next_step
    plastic("sync")
    plastic("backup")

    assert_match(/^archive\s+.*#{NAME}$/o, @fixture.printed)
    assert_includes @fixture.printed, "next: plastic backup --list"
  end

  def test_a_missing_database_exits_one_and_names_sync
    assert_equal 1, plastic("backup")
    assert_includes @fixture.warned, "plastic sync"
    assert_empty archives
  end

  def test_a_failed_run_leaves_no_file_in_backups
    plastic("sync")
    FileUtils.mkdir_p(File.join(home, "backups"))
    File.write(File.join(home, "knowledge_graph.db"), "not a database")

    assert_equal 1, plastic("backup")
    assert_empty archives
  end

  def test_list_prints_each_archive_with_its_size
    plastic("sync")
    plastic("backup")
    plastic("backup", "--list")

    assert_match(/^#{NAME}\s+\d+ bytes  \d{4}-\d{2}-\d{2} \d{2}:\d{2}$/o, @fixture.printed)
  end

  def test_list_with_no_archive_says_so
    plastic("backup", "--list")

    assert_includes @fixture.printed, "no backup yet"
  end
end
