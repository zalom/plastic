# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"

require_relative "../scripts/lib/store_discovery"

class StoreDiscoveryTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-store-discovery")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def mkstore(slug)
    dir = slug == "global" ? File.join(@home, "store") : File.join(@home, "projects", slug, "store")
    FileUtils.mkdir_p(dir)
    dir
  end

  def write_projects_yml(projects)
    File.write(File.join(@home, "projects.yml"), YAML.dump({ "projects" => projects }))
  end

  def test_global_and_registered_project_with_store_are_discovered
    mkstore("global")
    mkstore("plastic")
    write_projects_yml({ "plastic" => { "path" => "/tmp/plastic" } })

    result = StoreDiscovery.discover(@home)
    keys = result[:stores].map { |s| s[:key] }
    assert_includes keys, "global"
    assert_includes keys, "project:plastic"
    assert_empty result[:missing]
  end

  # THE superset guarantee (D1): a store on disk but NOT in projects.yml must still be
  # discovered. Missing it reproduces the destructive bug from the other side.
  def test_on_disk_store_not_registered_is_still_discovered
    mkstore("global")
    mkstore("ai-agents-resources")
    write_projects_yml({}) # not registered anywhere

    slugs = StoreDiscovery.known_slugs(@home)
    assert_includes slugs, "ai-agents-resources"
  end

  # D5: registered but no store directory. Must not crash, must not silently look empty.
  def test_registered_project_with_no_store_dir_is_reported_missing
    mkstore("global")
    write_projects_yml({ "ghost-project" => { "path" => "/tmp/ghost" } })

    result = StoreDiscovery.discover(@home)
    refute_includes result[:stores].map { |s| s[:slug] }, "ghost-project"
    assert(result[:missing].any? { |m| m[:slug] == "ghost-project" })
  end

  # A junk on-disk directory with no store/ and not registered (the real
  # `-Users-zlatko-apps-personal` shape found in the live store) is silently excluded:
  # neither a store nor a reportable missing project.
  def test_junk_project_dir_with_no_store_and_not_registered_is_excluded_quietly
    FileUtils.mkdir_p(File.join(@home, "projects", "-Users-zlatko-apps-personal"))
    write_projects_yml({})

    result = StoreDiscovery.discover(@home)
    refute_includes result[:stores].map { |s| s[:slug] }, "-Users-zlatko-apps-personal"
    refute(result[:missing].any? { |m| m[:slug] == "-Users-zlatko-apps-personal" })
  end

  def test_missing_projects_yml_does_not_raise
    mkstore("global")
    mkstore("plastic")
    # no projects.yml written at all

    result = StoreDiscovery.discover(@home)
    assert_includes result[:stores].map { |s| s[:slug] }, "plastic"
  end

  def test_no_global_store_is_omitted_not_crashed_on
    mkstore("plastic")
    result = StoreDiscovery.discover(@home)
    refute_includes result[:stores].map { |s| s[:key] }, "global"
  end

  def test_known_slugs_excludes_missing_registered_projects
    mkstore("global")
    write_projects_yml({ "ghost-project" => { "path" => "/tmp/ghost" } })
    slugs = StoreDiscovery.known_slugs(@home)
    refute_includes slugs, "ghost-project"
  end
end
