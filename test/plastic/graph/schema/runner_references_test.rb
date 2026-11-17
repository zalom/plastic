# frozen_string_literal: true

require "digest"
require_relative "../../../test_helper"

# The runner copies the kept files of references.db into knowledge and retires references.db only after reading them back.
class SchemaRunnerReferencesTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  def run_runner(home) = Plastic::Graph::SchemaRunner.new(home:, now: NOW).call

  def old_home = old_layout(fresh_home)

  def keep_two_files(home)
    SQLite3::Database.new(File.join(home, "stores", "alpha", "references.db")) do |db|
      { "notes/a.md" => "alpha bytes", "notes/b.bin" => "\x00\x01binary".b }.each do |name, data|
        db.execute("INSERT INTO sqlar (name, mode, mtime, sz, data, intent_id, sha256, origin_id) VALUES (?, 420, 1, ?, ?, '1', ?, 'o')", [name, data.bytesize, SQLite3::Blob.new(data), Digest::SHA256.hexdigest(data)])
      end
    end
  end

  def kept_bytes(home)
    database = SQLite3::Database.new(store_file(home, "knowledge_graph"), readonly: true)
    database.execute("SELECT name, data FROM sqlar ORDER BY name").to_h { |name, data| [name, data.b] }
  ensure
    database&.close
  end

  def test_two_kept_files_migrate_into_knowledge_with_the_same_bytes_and_references_db_is_gone
    home = old_home
    keep_two_files(home)
    run_runner(home)

    assert_equal({ "notes/a.md" => "alpha bytes", "notes/b.bin" => "\x00\x01binary".b }, kept_bytes(home))
    refute_path_exists File.join(home, "stores", "alpha", "references.db")
  end

  def leave_references(home, slug)
    SQLite3::Database.new(File.join(home, "stores", slug, "references.db")) { |db| db.execute_batch(Plastic::Graph::SchemaStore1::Layout::TEXT.fetch(:references)) }
  end

  def test_a_references_file_left_beside_a_migrated_knowledge_file_is_removed_by_the_next_run
    home = old_home
    run_runner(home)
    leave_references(home, "beta")
    run_runner(home)

    refute_path_exists File.join(home, "stores", "beta", "references.db")
  end

  def test_a_references_file_whose_rows_are_not_in_knowledge_is_kept
    home = old_home
    run_runner(home)
    leave_references(home, "alpha")
    keep_two_files(home)
    report = run_runner(home)

    assert_equal [["alpha"], true], [report.failed.keys, File.exist?(File.join(home, "stores", "alpha", "references.db"))]
  end
end
