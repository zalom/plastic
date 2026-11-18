# frozen_string_literal: true

require "minitest/autorun"

# Each kind of database has its own folder of migrations under db/migrate, and each file is named by a UTC timestamp.
class GraphMigrationsFolderTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  FOLDER = File.join(ROOT, "lib/plastic/graph/db/migrate")
  NAME = /\A\d{14}_[a-z0-9]+(?:_[a-z0-9]+)*\.sql\z/
  SCHEMA = File.join(ROOT, "lib/plastic/graph/db/schema.rb")

  def migration_files = Dir.glob(File.join(FOLDER, "*", "*"))

  def test_the_folder_holds_one_folder_for_the_home_and_one_for_the_store
    assert_equal %w[home store], Dir.children(FOLDER).sort
  end

  def test_the_store_folder_holds_the_store_baseline
    assert_includes Dir.children(File.join(FOLDER, "store")), "20261117000000_store_from_beta_2.sql"
  end

  def test_the_home_folder_holds_the_home_baseline
    assert_includes Dir.children(File.join(FOLDER, "home")), "20261117000000_plastic_db_from_local_db.sql"
  end

  def test_every_migration_is_named_by_a_14_digit_timestamp_and_a_snake_case_name
    refute_empty migration_files
    assert_empty migration_files.map { |path| File.basename(path) }.grep_v(NAME)
  end

  def test_the_version_of_the_schema_file_is_the_newest_migration_of_any_kind
    newest = migration_files.map { |path| File.basename(path)[0, 14] }.max

    assert_equal newest, File.read(SCHEMA)[/version: ([\d_]+)/, 1].delete("_")
  end

  def test_the_old_migrations_folder_is_gone
    refute_path_exists File.join(ROOT, "lib/plastic/graph/schema/migrations")
    refute_path_exists File.join(ROOT, "lib/plastic/graph/schema/migrations.rb")
  end
end
