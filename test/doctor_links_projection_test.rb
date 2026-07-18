# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"

# ACTION 5 — the new graph_links_projection doctor drift check. Hermetic temp
# homes. The check must flag any `## Links` section that does not EQUAL its
# frontmatter projection in BOTH membership AND ordering, and pass on a correctly
# projected store.
class DoctorLinksProjectionTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-links")
    [global_store, plastic_store].each { |d| FileUtils.mkdir_p(d) }
    write_index(File.join(@home, "INDEX.md"))
    write_index(File.join(@home, "projects", "plastic", "INDEX.md"))
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def global_store = File.join(@home, "store")
  def plastic_store = File.join(@home, "projects", "plastic", "store")

  def write_intent(scope_dir, basename, id:, intent:, sources:, chain:, links:)
    dir = File.join(scope_dir, basename)
    FileUtils.mkdir_p(dir)
    fm = +"---\nid: \"#{id}\"\nintent: \"#{intent}\"\n"
    fm << "sources: #{sources.inspect}\nchain: #{chain.inspect}\n"
    fm << "created: 2026-06-01\nauthor: t\ntags: [t]\n---\n\n"
    fm << "## Intent\nb\n\n#{links}"
    File.write(File.join(dir, "#{basename}.md"), fm)
  end

  def write_index(path, relocated: "(none)")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# Index\n\n## Relocated\n#{relocated}\n\n## Completed\n")
  end

  def doctor = Doctor.new(plastic_home: @home)

  def links_check(scopes: nil)
    doctor.check_conventions(scopes: scopes).find { |c| c[:name] == "graph_links_projection" }
  end

  # Targets used by the references below.
  def seed_targets
    write_intent(plastic_store, "40--store-graph", id: "40", intent: "Build the store graph",
                 sources: [], chain: [],
                 links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    write_intent(plastic_store, "60--bypass", id: "60", intent: "Block the bypass",
                 sources: [], chain: [],
                 links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
  end

  def test_legacy_placeholder_is_flagged
    seed_targets
    write_intent(plastic_store, "5--child", id: "5", intent: "Child",
                 sources: ["40"], chain: [],
                 links: "## Links\n<!-- Retroactive (intent 60b): heading only. -->\n")

    check = links_check
    assert_equal "warn", check[:status]
    assert(check[:details].any? { |d| d.start_with?("5 ## Links") })
  end

  def test_ordering_drift_flagged_even_with_correct_membership
    seed_targets
    # 5 has source 40 and chain 60. The CORRECT projection is 40 then 60. Here the
    # file lists chain (60) BEFORE source (40): correct membership, wrong order.
    misordered = "## Links\n" \
                 "- [[60--bypass|Block the bypass]]\n" \
                 "- [[40--store-graph|Build the store graph]]\n"
    write_intent(plastic_store, "5--child", id: "5", intent: "Child",
                 sources: ["40"], chain: ["60"], links: misordered)

    check = links_check
    assert_equal "warn", check[:status]
    assert(check[:details].any? { |d| d.start_with?("5 ## Links") },
           "a chain-before-source ordering must be flagged")
  end

  def test_empty_state_is_green
    write_intent(plastic_store, "13--lonely", id: "13", intent: "Lonely",
                 sources: [], chain: [],
                 links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    check = links_check
    assert_equal "pass", check[:status]
  end

  def test_green_when_correctly_projected
    seed_targets
    correct = "## Links\n" \
              "- [[40--store-graph|Build the store graph]]\n" \
              "- [[60--bypass|Block the bypass]]\n"
    write_intent(plastic_store, "5--child", id: "5", intent: "Child",
                 sources: ["40"], chain: ["60"], links: correct)

    check = links_check
    assert_equal "pass", check[:status]
  end

  def test_scope_filtering_hides_other_store_findings
    seed_targets
    write_intent(plastic_store, "5--child", id: "5", intent: "Child",
                 sources: ["40"], chain: [],
                 links: "## Links\n<!-- stale -->\n")
    # Scoping to global hides the plastic-origin drift finding.
    scoped = links_check(scopes: ["global"])
    assert_equal "pass", scoped[:status]
  end

  # Write an intent whose Context carries a ```markdown fence CONTAINING a
  # `## Links` heading, with the REAL `## Links` as the final section.
  def write_fenced_intent(basename, id:, intent:, sources:, chain:, real_links:)
    dir = File.join(plastic_store, basename)
    FileUtils.mkdir_p(dir)
    fm = +"---\nid: \"#{id}\"\nintent: \"#{intent}\"\n"
    fm << "sources: #{sources.inspect}\nchain: #{chain.inspect}\n"
    fm << "created: 2026-06-01\nauthor: t\ntags: [t]\n---\n\n"
    fm << "## Intent\nb\n\n## Context\n\nExample:\n```markdown\n## Links\n- [[1b1a]] old example\n```\n\n"
    fm << real_links
    File.write(File.join(dir, "#{basename}.md"), fm)
  end

  # REGRESSION (intent 72 corruption fix): the check must compare against the REAL
  # `## Links` section, not the heading inside the fenced example. With a CORRECTLY
  # projected real section, the check is GREEN despite the fenced example heading.
  def test_fenced_example_heading_does_not_create_false_finding
    correct = "## Links\n- [[40--store-graph|Build the store graph]]\n"
    # Seed the target referenced by the real section.
    write_intent(plastic_store, "40--store-graph", id: "40", intent: "Build the store graph",
                 sources: [], chain: [],
                 links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    write_fenced_intent("7--fenced", id: "7", intent: "Fenced",
                        sources: ["40"], chain: [], real_links: correct)

    check = links_check
    assert_equal "pass", check[:status],
                 "the fenced example heading must not be treated as the real section"
  end

  # When the REAL section under the fence is stale, the check still flags it (the
  # fence does not hide a genuinely-drifted real section).
  def test_fenced_file_with_stale_real_section_is_flagged
    write_intent(plastic_store, "40--store-graph", id: "40", intent: "Build the store graph",
                 sources: [], chain: [],
                 links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    write_fenced_intent("7--fenced", id: "7", intent: "Fenced",
                        sources: ["40"], chain: [],
                        real_links: "## Links\n- [[9--nine]] stale\n")

    check = links_check
    assert_equal "warn", check[:status]
    assert(check[:details].any? { |d| d.start_with?("7 ## Links") })
  end

  # ACTION_1 (intent 192): the fix_hint must no longer read as an unconditional
  # "regenerate" instruction; it must name the default-preserving behavior and
  # the opt-in flag, since running project-links used to be able to destroy an
  # unbacked-but-resolvable line (the dealintell 15 bug this intent fixes).
  def test_fix_hint_names_the_preserving_default_and_the_opt_in_flag
    seed_targets
    write_intent(plastic_store, "5--child", id: "5", intent: "Child",
                 sources: ["40"], chain: [],
                 links: "## Links\n<!-- Retroactive (intent 60b): heading only. -->\n")

    check = links_check
    refute_equal "Run scripts/project-links to regenerate the canonical ## Links sections",
                 check[:fix_hint],
                 "the fix_hint must no longer promise unconditional destructive regeneration"
    assert_includes check[:fix_hint], "--drop-unbacked-links"
    assert_includes check[:fix_hint], "PRESERVES"
  end

  # ACTION_11 (intent 197): the fix_hint must point at the maintenance-run wrapper (lock
  # detection, clean-tree precondition, scoped commit-plus-receipt), not just bare
  # project-links, so an agent following the hint runs the safe path by default.
  def test_fix_hint_names_maintenance_run
    seed_targets
    write_intent(plastic_store, "5--child", id: "5", intent: "Child",
                 sources: ["40"], chain: [],
                 links: "## Links\n<!-- Retroactive (intent 60b): heading only. -->\n")

    check = links_check
    assert_includes check[:fix_hint], "maintenance-run"
  end
end
