# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"
load File.expand_path("../scripts/rebuild-graph", __dir__)
load File.expand_path("../scripts/project-links", __dir__)

# Cross-tool agreement (intent 189's whole thesis): doctor, rebuild-graph, and
# project-links must enumerate the IDENTICAL set of stores for the same plastic_home,
# including a store outside the pre-fix hardcoded %w[plastic knowdb] list.
class StoreDiscoveryCrossToolTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-cross-tool")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_intent(store_dir, id)
    dir = File.join(store_dir, "#{id}--slug")
    FileUtils.mkdir_p(dir)
    fm = +"---\nid: \"#{id}\"\nintent: t\nsources: []\nchain: []\n"
    fm << "created: 2026-06-01\nauthor: t\ntags: [t]\n---\n\n## Intent\nb\n"
    File.write(File.join(dir, "#{id}--slug.md"), fm)
  end

  def write_index(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# Index\n\n## Relocated\n(none)\n\n## Completed\n")
  end

  def build_family
    global = File.join(@home, "store")
    plastic = File.join(@home, "projects", "plastic", "store")
    knowdb = File.join(@home, "projects", "knowdb", "store")
    aar = File.join(@home, "projects", "ai-agents-resources", "store")
    [global, plastic, knowdb, aar].each { |d| FileUtils.mkdir_p(d) }
    write_intent(global, "1")
    write_intent(plastic, "1")
    write_intent(knowdb, "1")
    write_intent(aar, "1")
    write_index(File.join(@home, "INDEX.md"))
    write_index(File.join(@home, "projects", "plastic", "INDEX.md"))
    write_index(File.join(@home, "projects", "knowdb", "INDEX.md"))
    write_index(File.join(@home, "projects", "ai-agents-resources", "INDEX.md"))
  end

  def test_doctor_rebuild_graph_and_project_links_agree
    build_family
    expected = %w[global project:ai-agents-resources project:knowdb project:plastic]

    doctor_scopes = Doctor.new(plastic_home: @home).all_intent_dirs.map { |d| d[:scope] }.uniq.sort
    rebuild_keys = RebuildGraph.new(plastic_home: @home).stores.map { |s| s[:key] }.sort
    links_keys = ProjectLinks.new(plastic_home: @home).stores.map { |s| s[:key] }.sort

    assert_equal expected, doctor_scopes
    assert_equal expected, rebuild_keys
    assert_equal expected, links_keys
  end
end
