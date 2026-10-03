# frozen_string_literal: true

require "zlib"
require "rubygems/package"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup"

class BackupTest < Plastic::TestCase
  def call(*args, env: {}) = plastic("backup", *args, env:, table: Plastic::CLI::TABLE)

  def entries_of(path)
    Zlib::GzipReader.open(path) do |gz|
      Gem::Package::TarReader.new(gz) { |tar| return tar.map { |entry| [entry.full_name, entry.read] } }
    end
  end

  # A real home is wrapped in a per-test transaction and rolled back, as
  # Rails rolls each test back, so a connection inside it is always mid
  # transaction. VACUUM INTO never runs inside one, so backup is proved
  # against a plain, separate home that commits as a real process would.
  def populated_home(title: "Target")
    home = File.join(Dir.mktmpdir, ".plastic")
    env = { "PLASTIC_HOME" => home }

    assert_equal 0, plastic("intent", "new", title, env:, table: Plastic::CLI::TABLE).code
    [home, env]
  end

  def archive_path(env)
    result = call(env:)

    assert_equal 0, result.code
    name = result.out[/backup: (\S+),/, 1]
    File.join(env.fetch("PLASTIC_HOME"), "backups", name)
  end

  def at(time)
    singleton = Time.singleton_class
    original = Time.method(:now)
    singleton.define_method(:now) { time }
    yield
  ensure
    singleton.define_method(:now, original)
  end

  def test_the_archive_lists_home_and_every_store_database
    _home, env = populated_home

    names = entries_of(archive_path(env)).map(&:first)
    expected = %w[home.db stores/global/work_graph.db stores/global/knowledge_graph.db stores/global/references.db]

    assert_empty expected - names
  end

  def test_every_entry_opens_as_sqlite
    _home, env = populated_home

    Dir.mktmpdir do |tmp|
      entries_of(archive_path(env)).each do |name, bytes|
        next unless name.end_with?(".db")

        path = File.join(tmp, name.tr("/", "_"))
        File.binwrite(path, bytes)

        assert_equal [], SQLite3::Database.new(path, readonly: true).execute("PRAGMA integrity_check")
          .reject { |row| row == ["ok"] }
      end
    end
  end

  def test_a_deeply_nested_home_backs_up
    deep = File.join(Dir.mktmpdir, "d" * 60, "e" * 60, "f" * 60, "g" * 60)

    result = call(env: { "PLASTIC_HOME" => deep })

    assert_equal 0, result.code
    assert_predicate Dir.glob(File.join(deep, "backups", "*.tar.gz")), :any?
  end

  def test_an_unpacked_backup_retains_identity_configuration_and_rows
    home, env = populated_home
    File.write(File.join(home, "config.yml"), "hooks:\n  stop: false\n")
    File.write(File.join(home, "projects.yml"), "projects: {}\n")
    entries = entries_of(archive_path(env))

    Dir.mktmpdir do |restored|
      unpack(entries, restored)

      assert_home_files_match(home, restored)
      assert_restored_intent(restored)
    end
  end

  def test_same_second_backups_keep_distinct_readable_archives_and_metadata
    _home, env = populated_home
    time = Time.utc(2026, 10, 3, 12, 0, 0)

    first = at(time) { archive_path(env) }
    assert_equal 0, plastic("intent", "new", "Changed state", env:, table: Plastic::CLI::TABLE).code
    second = at(time) { archive_path(env) }

    refute_equal first, second
    assert_equal 2, Dir.glob(File.join(env.fetch("PLASTIC_HOME"), "backups", "*.tar.gz")).size
    assert_equal [first, second].sort, retrieval_backups(env).sort
    assert_equal ["Target"], archive_titles(first)
    assert_equal %w[Changed\ state Target], archive_titles(second)
  end

  def test_backup_dry_run_reports_the_planned_archive_without_creating_a_home
    home = File.join(Dir.mktmpdir, ".plastic")
    result = call("--dry-run", env: { "PLASTIC_HOME" => home })

    assert_equal 0, result.code
    assert_includes result.out, "preview"
    refute_path_exists home
  end

  def assert_home_files_match(home, restored)
    %w[origin_id config.yml projects.yml].each do |name|
      assert_equal File.binread(File.join(home, name)), File.binread(File.join(restored, name))
    end
  end

  def assert_restored_intent(home)
    result = plastic("intent", "show", "1", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_includes result.out, "Target"
  end

  def unpack(entries, home)
    entries.each do |name, bytes|
      path = File.join(home, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, bytes)
    end
  end

  def retrieval_backups(env)
    Plastic::Graph.open(home: env.fetch("PLASTIC_HOME"), store: "global").retrieval.backups.map do |backup|
      File.join(env.fetch("PLASTIC_HOME"), "backups", backup.name)
    end
  end

  def archive_titles(path)
    entries_of(path).filter_map do |name, bytes|
      next unless name == "stores/global/work_graph.db"

      database = SQLite3::Database.new(":memory:")
      database.deserialize(bytes)
      database.execute("SELECT title FROM intents ORDER BY intent_id").flatten
    end.flatten
  end
end
