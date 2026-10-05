# frozen_string_literal: true

require_relative "test_helper"
require "store_layout"

class StoreLayoutTest < Plastic::TestCase
  def home
    File.join(@home, "layout")
  end

  def moved_home
    FileUtils.mkdir_p(File.join(home, "stores"))
    home
  end

  def test_a_home_with_a_stores_folder_has_moved
    assert Plastic::StoreLayout.moved?(moved_home)
  end

  def test_a_home_without_a_stores_folder_has_not_moved
    refute Plastic::StoreLayout.moved?(home)
  end

  def test_a_moved_home_keeps_the_global_store_under_stores_global
    assert_equal File.join(home, "stores", "global", "store"), Plastic::StoreLayout.global_store(moved_home)
  end

  def test_a_home_that_has_not_moved_keeps_the_global_store_at_its_root
    assert_equal File.join(home, "store"), Plastic::StoreLayout.global_store(home)
  end

  def test_a_home_that_has_not_moved_keeps_projects_under_projects
    assert_equal File.join(home, "projects", "alpha"), Plastic::StoreLayout.root(home, "alpha")
  end

  def test_the_global_slug_resolves_to_the_global_root
    assert_equal File.join(home, "stores", "global"), Plastic::StoreLayout.root(moved_home, "global")
  end

  def test_project_slugs_skip_the_global_store_and_hidden_folders
    %w[beta alpha global .cache].each { |slug| FileUtils.mkdir_p(File.join(moved_home, "stores", slug)) }

    assert_equal %w[alpha beta], Plastic::StoreLayout.project_slugs(home)
  end

  def test_project_slugs_are_empty_when_the_projects_folder_is_missing
    assert_empty Plastic::StoreLayout.project_slugs(home)
  end

  def test_a_project_store_names_its_home_and_its_project_scope
    store = File.join(home, "stores", "alpha", "store")

    assert_equal [home, "project:alpha"], Plastic::StoreLayout.home_and_scope(store)
  end

  def test_a_store_outside_the_project_parents_is_the_global_store
    assert_equal [home, "global"], Plastic::StoreLayout.home_and_scope(File.join(home, "store"))
  end
end
