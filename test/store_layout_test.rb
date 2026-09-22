# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/store_layout"

class StoreLayoutTest < Minitest::Test
  Layout = Plastic::StoreLayout

  def setup
    @home = Dir.mktmpdir("plastic-layout")
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  def make(*parts)
    FileUtils.mkdir_p(File.join(@home, *parts))
  end

  def test_a_home_with_no_projects_directory_has_no_slugs
    assert_empty Layout.project_slugs(@home)
  end

  def test_the_old_layout_lists_its_projects_sorted_without_hidden_entries
    %w[zeta acme .git].each { |entry| make("projects", entry) }

    assert_equal %w[acme zeta], Layout.project_slugs(@home)
  end

  def test_the_new_layout_lists_its_projects_without_the_global_store
    %w[global acme].each { |entry| make("stores", entry) }

    assert_equal %w[acme], Layout.project_slugs(@home)
  end

  def test_a_project_store_is_located_in_both_layouts
    assert_equal [@home, "acme"], Layout.locate(File.join(@home, "projects", "acme", "store"))
    assert_equal [@home, "acme"], Layout.locate(File.join(@home, "stores", "acme", "store"))
  end

  def test_the_global_store_is_located_in_both_layouts
    assert_equal [@home, "global"], Layout.locate(File.join(@home, "store"))
    assert_equal [@home, "global"], Layout.locate(File.join(@home, "stores", "global", "store"))
  end

  def test_the_scope_names_the_project
    assert_equal [@home, "project:acme"], Layout.home_and_scope(File.join(@home, "stores", "acme", "store"))
    assert_equal [@home, "global"], Layout.home_and_scope(File.join(@home, "store"))
  end
end
