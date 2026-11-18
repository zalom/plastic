# frozen_string_literal: true

require "tmpdir"
require_relative "../../../test_helper"

class MigrationListTest < Plastic::TestCase
  MigrationList = Plastic::Graph::MigrationList
  SchemaMigration = Plastic::Graph::SchemaMigration

  def folder_with(names)
    folder = Dir.mktmpdir("migrate", @home)
    names.each do |name|
      FileUtils.mkdir_p(File.join(folder, File.dirname(name)))
      File.write(File.join(folder, name), "SELECT 1;")
    end
    folder
  end

  def test_the_list_of_the_code_is_frozen_and_read_once
    assert_predicate Plastic::Graph::MIGRATIONS, :frozen?
    assert_same Plastic::Graph::MIGRATIONS, Plastic::Graph::MIGRATIONS
  end

  def test_the_list_of_the_code_names_the_baseline_of_each_kind
    assert_equal %w[20261117000000 20261117000000], [Plastic::Graph::MIGRATIONS.baseline(:home), Plastic::Graph::MIGRATIONS.baseline(:store)]
  end

  def test_the_versions_of_a_kind_come_in_ascending_order
    list = MigrationList.read(folder_with(%w[store/20270101000000_later.sql store/20261117000000_first.sql home/20260101000000_home.sql]))

    assert_equal %w[20261117000000 20270101000000], list.versions(:store)
  end

  def test_the_newest_of_any_kind_is_the_highest_version_across_the_kinds
    list = MigrationList.read(folder_with(%w[store/20261117000000_first.sql home/20280101000000_home.sql]))

    assert_equal "20280101000000", list.newest_of_any
  end

  def test_a_list_with_one_more_migration_keeps_the_first_unchanged
    list = MigrationList.read(folder_with(%w[store/20261117000000_first.sql]))
    longer = list.with(SchemaMigration.new(kind: :store, version: "20990101000000", path: "/nowhere.sql"))

    assert_equal [%w[20261117000000], %w[20261117000000 20990101000000]], [list.versions(:store), longer.versions(:store)]
  end

  def test_the_stamp_of_an_alpha_build_reads_as_the_baseline_version
    list = Plastic::Graph::MIGRATIONS

    assert_equal [0, 20_261_117_000_000, 20_261_117_000_000], [list.number(:store, 0), list.number(:store, 1), list.number(:store, 20_261_117_000_000)]
  end

  def test_a_number_is_known_when_it_is_zero_or_a_version_of_the_kind
    list = Plastic::Graph::MIGRATIONS

    assert_equal [true, true, false, false], [0, 20_261_117_000_000, 20_991_231_000_000, 99].map { |number| list.known_number?(:store, number) }
  end
end
