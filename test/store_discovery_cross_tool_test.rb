# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"
require_relative "../scripts/lib/intent_validator"
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

  def write_intent_with_chain(store_dir, id, chain)
    dir = File.join(store_dir, "#{id}--slug")
    FileUtils.mkdir_p(dir)
    chain_yaml = chain.empty? ? "[]" : "[#{chain.map { |c| "\"#{c}\"" }.join(", ")}]"
    fm = +"---\nid: \"#{id}\"\nintent: t\nsources: []\nchain: #{chain_yaml}\n"
    fm << "created: 2026-06-01\nauthor: t\ntags: [t]\n---\n\n## Intent\nb\n"
    File.write(File.join(dir, "#{id}--slug.md"), fm)
  end

  # Finding 1 (independent review of intent 189): a store that exists on disk with
  # ZERO intents (the normal state right after StoreProvisioning, before its first
  # intent lands) must classify a ref into it the SAME way in doctor as in
  # rebuild-graph: :dead, never :unknown_store. Doctor's store_index used to gain a
  # key only when a valid intent was found, so a real-but-empty store had no key and
  # a ref into it looked undiscovered, even though StoreDiscovery reports the store.
  def test_doctor_and_rebuild_graph_agree_ref_into_real_empty_store_is_dead
    global = File.join(@home, "store")
    empty_store = File.join(@home, "projects", "emptyproj", "store")
    FileUtils.mkdir_p(global)
    FileUtils.mkdir_p(empty_store)
    write_intent_with_chain(global, "1", ["emptyproj:5"])
    write_index(File.join(@home, "INDEX.md"))
    write_index(File.join(@home, "projects", "emptyproj", "INDEX.md"))

    check = Doctor.new(plastic_home: @home).check_conventions
                  .find { |c| c[:name] == "graph_cross_store_resolution" }
    assert_equal "warn", check[:status]
    assert(
      check[:details].any? { |d| d.include?("emptyproj:5") && d.include?("dead") },
      "doctor must classify a ref into a real, empty store as dead: #{check[:details].inspect}"
    )
    refute(
      check[:details].any? { |d| d.include?("emptyproj:5") && d.include?("does not recognize") },
      "the store IS discovered by StoreDiscovery; it just holds zero intents, so this " \
      "must not read as unknown_store"
    )

    audit = File.join(@home, "audit.md")
    RebuildGraph.new(plastic_home: @home, dry_run: false, audit_path: audit).run
    fm = IntentValidator.parse_frontmatter(File.join(global, "1--slug", "1--slug.md"))
    refute_includes fm["chain"], "emptyproj:5",
                     "rebuild-graph must drop the ref: the store is known and id 5 is absent from it"
  end
end
