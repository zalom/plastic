# frozen_string_literal: true

require_relative "../test_helper"
require "plastic/store_layout"

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
end
