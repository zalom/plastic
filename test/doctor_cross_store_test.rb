# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

require_relative "../scripts/doctor"

# ACTION 4 — the new doctor cross-store-resolution drift check. Hermetic temp
# homes; the check must RESOLVE refs across all stores (relocation-first), catching
# the id-reuse hazard that shape-only i1/i3/i4 silently accept.
class DoctorCrossStoreTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-cross-store")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_intent(scope_dir, id, sources:, chain:)
    dir = File.join(scope_dir, "#{id}--slug")
    FileUtils.mkdir_p(dir)
    fm = +"---\nid: \"#{id}\"\nintent: t\n"
    fm << "sources: #{sources.inspect}\nchain: #{chain.inspect}\n"
    fm << "created: 2026-06-01\nauthor: t\ntags: [t]\n---\n\n"
    fm << "## Intent\nb\n\n## Context\nc\n\n## Outcome\no\n\n## Insights\ni\n\n## Links\n- x\n"
    File.write(File.join(dir, "#{id}--slug.md"), fm)
  end

  def write_index(path, relocated: "(none)")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# Index\n\n## Active\n\n## Future\n\n## Clusters\n\n" \
                     "## Abandoned\n\n## Completed\n\n## Relocated\n#{relocated}\n")
  end

  def global_store = File.join(@home, "store")
  def plastic_store = File.join(@home, "projects", "plastic", "store")
  def knowdb_store = File.join(@home, "projects", "knowdb", "store")

  def setup_family
    [global_store, plastic_store, knowdb_store].each { |d| FileUtils.mkdir_p(d) }
    write_index(File.join(@home, "INDEX.md"),
                relocated: "- global:14a → project:19a, global:24 → project:22c")
    write_index(File.join(@home, "projects", "plastic", "INDEX.md"))
    write_index(File.join(@home, "projects", "knowdb", "INDEX.md"))
  end

  def doctor = Doctor.new(plastic_home: @home)

  def cross_store_check(scopes: nil)
    doctor.check_conventions(scopes: scopes).find { |c| c[:name] == "graph_cross_store_resolution" }
  end

  # The id-reuse HAZARD is now CAUGHT (was invisible before): a live unrelated
  # global:24 exists, but plastic:11.sources=[global:24] is relocated-stale.
  def test_relocated_stale_id_reuse_hazard_is_flagged
    setup_family
    write_intent(global_store, "24", sources: [], chain: []) # impostor present
    write_intent(plastic_store, "11", sources: ["global:24"], chain: [])
    write_intent(plastic_store, "22c", sources: [], chain: [])

    check = cross_store_check
    assert_equal "warn", check[:status]
    assert(check[:details].any? { |d| d.include?("11.sources") && d.include?("global:24") && d.include?("relocated-stale") })
  end

  def test_dead_cross_store_ref_flagged
    setup_family
    write_intent(plastic_store, "11", sources: ["global:999"], chain: [])

    check = cross_store_check
    assert_equal "warn", check[:status]
    assert(check[:details].any? { |d| d.include?("global:999") && d.include?("dead") })
  end

  def test_healthy_live_cross_store_ref_is_green
    setup_family
    write_intent(global_store, "1a2", sources: [], chain: ["knowdb:1"])
    write_intent(knowdb_store, "1", sources: ["global:1a2"], chain: [])

    check = cross_store_check
    assert_equal "pass", check[:status]
  end

  # Resolution spans stores even under a single --store scope: scoping plastic must
  # still resolve global:24 against the global store and flag it.
  def test_resolution_spans_stores_under_single_scope
    setup_family
    write_intent(global_store, "24", sources: [], chain: [])
    write_intent(plastic_store, "11", sources: ["global:24"], chain: [])
    write_intent(plastic_store, "22c", sources: [], chain: [])

    scoped = cross_store_check(scopes: ["project:plastic"])
    assert_equal "warn", scoped[:status]
    assert(scoped[:details].any? { |d| d.include?("11.sources") })
  end

  # Findings filtered by origin scope: scoping global hides a plastic-origin finding.
  def test_findings_filtered_by_origin_scope
    setup_family
    write_intent(global_store, "24", sources: [], chain: [])
    write_intent(plastic_store, "11", sources: ["global:24"], chain: [])
    write_intent(plastic_store, "22c", sources: [], chain: [])

    scoped_global = cross_store_check(scopes: ["global"])
    assert_equal "pass", scoped_global[:status], "plastic-origin finding not reported under --store global"
  end

  # After the rebuild repoints the ref to bare 22c, the check is GREEN.
  def test_green_after_rebuild_repoint
    setup_family
    write_intent(global_store, "24", sources: [], chain: [])
    write_intent(plastic_store, "11", sources: ["22c"], chain: []) # already repointed
    write_intent(plastic_store, "22c", sources: [], chain: ["11"])

    check = cross_store_check
    assert_equal "pass", check[:status]
  end
end
