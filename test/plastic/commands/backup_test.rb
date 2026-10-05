# frozen_string_literal: true

require "zlib"
require "rubygems/package"
require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup"

module BackupTestSupport
  def call(*args, env: {}) = plastic("backup", *args, env:, table: Plastic::CLI::TABLE)

  def entries_of(path)
    Zlib::GzipReader.open(path) do |gz|
      Gem::Package::TarReader.new(gz) { |tar| return tar.map { |entry| [entry.full_name, entry.read] } }
    end
  end

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

  def unpack(entries, home)
    entries.each do |name, bytes|
      path = File.join(home, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, bytes)
    end
  end
end

class BackupTest < Plastic::TestCase
  include BackupTestSupport

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
end

class BackupRetrievalTest < Plastic::TestCase
  include BackupTestSupport

  def test_an_unpacked_backup_retains_the_owning_retrieval_context_rows
    home, env = populated_home
    graphs = Plastic::Graph.open(home:, store: "global")
    body = JSON.generate("intent_id" => "1", "facts" => ["kept"])
    graphs.databases.fetch(:knowledge).transaction do |batch|
      batch.put(:retrieval_contexts, { intent_id: "1", data: body, updated_at: STAMP })
    end

    Dir.mktmpdir do |restored|
      unpack(entries_of(archive_path(env)), restored)

      assert_context_row(restored, body)
    end
  end

  def test_backup_unpack_and_cli_readback_keep_retrieval_handoff_rows
    home, env = populated_home
    reference = write_retrieval_document(home, "backup evidence")
    discovery = plastic("intent", "discover", "1", "backup", "--json", env:, table: Plastic::CLI::TABLE)

    assert_equal [0, "backup", ""], [discovery.code, JSON.parse(discovery.out).dig("result", "discovery", "query"), discovery.err]
    submit_retrieval_context(env, reference)

    Dir.mktmpdir do |restored|
      unpack(entries_of(archive_path(env)), restored)

      assert_retrieval_readback(restored)
    end
  end

  def assert_context_row(restored, body)
    row = Plastic::Graph.open(home: restored, store: "global").databases.fetch(:knowledge).row("SELECT data FROM retrieval_contexts WHERE intent_id = '1'")

    assert_equal body, row.fetch("data")
  end

  def write_retrieval_document(home, body)
    graphs = Plastic::Graph.open(home:, store: "global")
    Plastic::Graph::Retrieval::Evidence::Writer.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id).write("1", "evidence.md", body)
    graphs.retrieval.backfill
    graphs.retrieval.reference("1", "evidence.md").fetch(:uri)
  end

  def submit_retrieval_context(env, reference)
    document = { "evidence" => [reference], "facts" => ["backup evidence"], "interpretations" => [], "gaps" => [], "rulings" => [] }
    Tempfile.create(["context", ".json"]) do |file|
      file.write(JSON.generate(document))
      file.flush
      result = plastic("intent", "context", "1", "--from", file.path, env:, table: Plastic::CLI::TABLE)

      assert_equal 0, result.code
    end
  end

  def assert_retrieval_readback(restored)
    restored_env = { "PLASTIC_HOME" => restored }
    readback = plastic("intent", "context", "1", "--json", env: restored_env, table: Plastic::CLI::TABLE)
    rows = Plastic::Graph.open(home: restored, store: "global").databases.fetch(:knowledge)

    assert_equal 0, readback.code
    assert_equal ["backup evidence"], JSON.parse(readback.out).dig("result", "context", "facts")
    assert rows.row("SELECT data FROM retrieval_discoveries WHERE intent_id = '1'")
    assert rows.row("SELECT data FROM retrieval_contexts WHERE intent_id = '1'")
  end
end
