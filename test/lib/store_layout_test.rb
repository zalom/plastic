# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/lib/store_layout"

class StoreLayoutTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-layout")
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  def make(*parts)
    FileUtils.mkdir_p(File.join(@home, *parts))
  end

  def test_the_old_layout_is_read_when_stores_is_absent
    make("projects", "acme")

    assert_equal File.join(@home, "store"), Plastic::StoreLayout.global_store(@home)
    assert_equal File.join(@home, "projects", "acme"), Plastic::StoreLayout.project_root(@home, "acme")
  end

  def test_the_new_layout_wins_when_stores_exists
    make("stores", "global")
    make("projects", "acme")

    assert_equal File.join(@home, "stores", "global", "store"), Plastic::StoreLayout.global_store(@home)
    assert_equal File.join(@home, "stores", "acme"), Plastic::StoreLayout.project_root(@home, "acme")
  end

  def test_the_project_slugs_leave_out_the_global_store_and_hidden_entries
    make("stores", "global")
    make("stores", "acme")
    make("stores", ".tmp")

    assert_equal ["acme"], Plastic::StoreLayout.project_slugs(@home)
  end

  def test_a_home_with_no_project_directory_has_no_slugs
    assert_empty Plastic::StoreLayout.project_slugs(@home)
  end

  def test_an_old_home_lists_its_projects
    make("projects", "acme")
    make("projects", "beta")

    assert_equal %w[acme beta], Plastic::StoreLayout.project_slugs(@home)
  end

  def test_the_root_of_the_global_slug_is_the_home_until_the_move
    assert_equal @home, Plastic::StoreLayout.root(@home, "global")
    make("stores")

    assert_equal File.join(@home, "stores", "global"), Plastic::StoreLayout.root(@home, "global")
    assert_equal File.join(@home, "stores", "acme"), Plastic::StoreLayout.root(@home, "acme")
  end

  def test_locate_names_the_home_and_the_slug_in_both_layouts
    assert_equal [@home, "global"], Plastic::StoreLayout.locate(File.join(@home, "store"))
    assert_equal [@home, "acme"], Plastic::StoreLayout.locate(File.join(@home, "projects", "acme", "store"))
    assert_equal [@home, "global"], Plastic::StoreLayout.locate(File.join(@home, "stores", "global", "store"))
  end

  def test_locate_names_a_moved_project
    assert_equal [@home, "acme"], Plastic::StoreLayout.locate(File.join(@home, "stores", "acme", "store"))
  end

  def test_the_scope_of_a_store_is_global_or_the_project_key
    assert_equal [@home, "global"], Plastic::StoreLayout.home_and_scope(File.join(@home, "stores", "global", "store"))
    assert_equal [@home, "project:acme"], Plastic::StoreLayout.home_and_scope(File.join(@home, "stores", "acme", "store"))
  end
end
