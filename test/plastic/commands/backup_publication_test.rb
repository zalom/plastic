# frozen_string_literal: true

require "zlib"
require "rubygems/package"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup"

class BackupMetadataFailureBatch
  def put(*) = raise Plastic::Graph::Database::Error, "injected metadata failure"
end

class BackupMetadataFailureDatabase
  def initialize(database) = @database = database

  def transaction
    @database.transaction { yield BackupMetadataFailureBatch.new }
  end
end

class BackupPublicationTest < Plastic::TestCase
  def test_same_second_backups_keep_distinct_readable_archives_and_metadata
    env = populated_home
    first, second = backups_at_same_time(env)

    assert_equal [first, second].sort, backup_paths(env).sort
    assert_equal [["Changed state", "Target"], ["Target"]], [archive_titles(first).sort, archive_titles(second).sort].sort
    assert_equal [first, second].sort, retrieval_backups(env).sort
  end

  def test_backup_publication_refuses_to_replace_an_existing_archive
    writer, staged, existing = collision_fixture

    assert_raises(Errno::EEXIST) { writer.publish(staged) }
    assert_equal "earlier archive", File.binread(existing)
    writer.discard(staged)

    assert_path_exists existing
  end

  def test_metadata_failure_removes_the_new_archive_and_preserves_prior_state
    env = populated_home
    prior = archive_path(env)
    home = env.fetch("PLASTIC_HOME")
    graphs = Plastic::Graph.open(home:, store: "global")
    database = BackupMetadataFailureDatabase.new(graphs.databases.fetch(:home))

    assert_raises(Plastic::Graph::Database::Error) { Plastic::Graph::BackupPublisher.new(database, home).call }
    assert_equal [prior], backup_paths(env)
    assert_equal [prior], retrieval_backups(env)
  end

  def test_staging_failure_removes_its_partial_hidden_archive
    home = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(home, "home.db"))

    assert_raises(SQLite3::CantOpenException) { Plastic::Graph::BackupWriter.new(home).stage }
    assert_empty Dir.glob(File.join(home, "backups", ".*.tmp"))
  end

  def test_backup_preview_agrees_with_apply_on_an_unchanged_disposable_home
    env = populated_home
    preview = plastic("backup", "--dry-run", env:, table: Plastic::CLI::TABLE)
    applied = archive_path(env)

    assert_equal 0, preview.code
    assert_includes preview.out, File.basename(applied)
  end

  private

  def populated_home
    home = File.join(Dir.mktmpdir, ".plastic")
    env = { "PLASTIC_HOME" => home }

    assert_equal 0, plastic("intent", "new", "Target", env:, table: Plastic::CLI::TABLE).code
    env
  end

  def backups_at_same_time(env)
    at(Time.utc(2026, 10, 3, 12, 0, 0)) do
      first = archive_path(env)

      assert_equal 0, plastic("intent", "new", "Changed state", env:, table: Plastic::CLI::TABLE).code
      [first, archive_path(env)]
    end
  end

  def archive_path(env)
    result = plastic("backup", env:, table: Plastic::CLI::TABLE)
    name = result.out[/backup: (\S+),/, 1]
    File.join(env.fetch("PLASTIC_HOME"), "backups", name)
  end

  def collision_fixture
    home = Dir.mktmpdir
    backups = File.join(home, "backups")
    existing = File.join(backups, "plastic-existing.tar.gz")
    staged_path = File.join(backups, ".plastic-existing.tar.gz.pending")
    FileUtils.mkdir_p(backups)
    File.binwrite(existing, "earlier archive")
    File.binwrite(staged_path, "new archive")
    staged = Plastic::Graph::BackupWriter::Staged.new(row: { name: File.basename(existing) }, path: staged_path)
    [Plastic::Graph::BackupWriter.new(home), staged, existing]
  end

  def at(time)
    singleton = Time.singleton_class
    original = Time.method(:now)
    singleton.define_method(:now) { time }
    yield
  ensure
    singleton.define_method(:now, original)
  end

  def backup_paths(env) = Dir.glob(File.join(env.fetch("PLASTIC_HOME"), "backups", "*.tar.gz"))

  def retrieval_backups(env)
    Plastic::Graph.open(home: env.fetch("PLASTIC_HOME"), store: "global").retrieval.backups.map do |backup|
      File.join(env.fetch("PLASTIC_HOME"), "backups", backup.name)
    end
  end

  def archive_titles(path)
    entry = entries_of(path).find { |name, _bytes| name == "stores/global/work_graph.db" }
    Dir.mktmpdir do |tmp|
      database_path = File.join(tmp, "work_graph.db")
      File.binwrite(database_path, entry.last)
      SQLite3::Database.new(database_path, readonly: true).execute("SELECT title FROM intents ORDER BY intent_id").flatten
    end
  end

  def entries_of(path)
    Zlib::GzipReader.open(path) do |gz|
      Gem::Package::TarReader.new(gz) { |tar| return tar.map { |entry| [entry.full_name, entry.read] } }
    end
  end
end
