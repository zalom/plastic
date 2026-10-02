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
end
