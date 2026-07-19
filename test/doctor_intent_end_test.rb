# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/outcome_guard"

# Intent 222 - doctor's fourth check scope, `--intent <id>`, verifies ONE intent's structure
# at the moment it is about to close: intent-file validity, lifecycle-artifact presence,
# checklist completeness, ## Links projection, and savepoint truthfulness. Four FAIL-severity
# checks plus one WARN-only (intent_savepoint_truthful, per intent 134's binding advisory-only
# ruling - see the WARN-not-FAIL test below). Hermetic: own Dir.mktmpdir store, no ambient
# session, no eval, no ENV/global-constant seam.
class DoctorIntentEndTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-intent-end")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def global_store = File.join(@home, "store")

  def doctor(plastic_home: @home) = Doctor.new(plastic_home: plastic_home)

  # Write a fully clean, complete intent: valid frontmatter and sections, real
  # spec/plan/checklist (checklist fully checked)/outcome, a correct savepoint born line, and
  # a `## Links` section matching the canonical empty-state projection (no sources/chain).
  # Every one of check_intent_end's 5 checks passes cleanly on the result unless a test
  # mutates exactly one thing away from it.
  def write_clean_intent(id:, slug: "demo", store_dir: global_store, sources: [], chain: [])
    dir = File.join(store_dir, "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--#{slug}.md"), <<~MD)
      ---
      id: "#{id}"
      intent: "Demo intent #{id}"
      sources: #{sources.inspect}
      chain: #{chain.inspect}
      created: 2026-07-01
      author: human
      tags: []
      ---

      ## Intent
      Demo intent #{id}

      ## Context

      ## Outcome
      (the result)

      ## Insights

      ## Links
      <!-- No sources or chain; this intent has no graph edges to project. -->
    MD
    File.write(File.join(dir, "spec.md"), "Tier: S\n\n# Spec: Demo intent #{id}\n")
    File.write(File.join(dir, "plan.md"), "# Plan: Demo intent #{id}\n\n- [x] Step 1\n")
    File.write(File.join(dir, "checklist.md"), "# Checklist: Demo intent #{id}\n\n- [x] Step 1\n")
    File.write(File.join(dir, "outcome.md"),
               "---\ndisposition: delivered\n---\n# Outcome: Demo intent #{id}\n\n## Summary\nDid it.\n")
    File.write(File.join(dir, "savepoint.md"), "2026-07-01T00:00:00Z  What  #{id}--#{slug}.md\n")
    dir
  end

  def find(checks, name) = checks.find { |c| c[:name] == name }

  # --- intent_structure -------------------------------------------------------

  def test_intent_structure_fails_on_malformed_frontmatter
    dir = write_clean_intent(id: "40")
    md = File.join(dir, "40--demo.md")
    content = File.read(md)
    File.write(md, content.sub("tags: []\n", "")) # drop a required field

    checks = doctor.check_intent_end("40")
    result = find(checks, "intent_structure")
    assert_equal "fail", result[:status]
    assert(result[:details].any? { |d| d.include?("tags") }, "expected the missing field named: #{result[:details].inspect}")
  end

  # --- intent_lifecycle_artifacts ---------------------------------------------

  def test_lifecycle_artifacts_fails_on_missing_outcome
    dir = write_clean_intent(id: "41")
    File.delete(File.join(dir, "outcome.md"))

    checks = doctor.check_intent_end("41")
    result = find(checks, "intent_lifecycle_artifacts")
    assert_equal "fail", result[:status]
    assert(result[:details].any? { |d| d.include?("outcome.md") }, result[:details].inspect)

    # D3: OutcomeGuard.reason is the SAME shared definition scripts/end-intent's own step-1
    # guard calls; proves it independently returns the identical missing-file text.
    reason = OutcomeGuard.reason(dir, "delivered")
    assert_match(/outcome\.md is missing/i, reason)
  end

  def test_lifecycle_artifacts_folds_in_outcome_disposition_mismatch
    dir = write_clean_intent(id: "42")
    File.write(File.join(dir, "outcome.md"),
               "---\ndisposition: abandoned\n---\n# Outcome\n\n## Summary\nDid it.\n")

    checks = doctor.check_intent_end("42", disposition: "delivered")
    assert_equal 5, checks.size
    lifecycle_checks = checks.select { |c| c[:name] == "intent_lifecycle_artifacts" }
    assert_equal 1, lifecycle_checks.size, "the disposition mismatch must fold into the SAME check, not a second one"

    result = lifecycle_checks.first
    assert_equal "fail", result[:status]
    assert(result[:details].any? { |d| d.include?("disposition") }, result[:details].inspect)
  end

  # --- intent_checklist_complete -----------------------------------------------

  def test_checklist_complete_fails_on_unchecked_item
    dir = write_clean_intent(id: "43")
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n- [x] done\n- [ ] still open\n")

    checks = doctor.check_intent_end("43")
    result = find(checks, "intent_checklist_complete")
    assert_equal "fail", result[:status]
    assert(result[:details].any? { |d| d.include?("still open") }, result[:details].inspect)
  end

  def test_checklist_complete_passes_when_absent
    dir = write_clean_intent(id: "44")
    File.delete(File.join(dir, "checklist.md"))

    checks = doctor.check_intent_end("44")
    result = find(checks, "intent_checklist_complete")
    assert_equal "pass", result[:status], "n/a (absent) must not double-report the lifecycle gap as a second fail"
  end

  # --- intent_links_projection --------------------------------------------------

  def test_links_projection_fails_only_for_the_named_id
    write_clean_intent(id: "60")
    write_clean_intent(id: "61")
    corrupted_md = File.join(global_store, "60--demo", "60--demo.md")
    content = File.read(corrupted_md)
    File.write(corrupted_md, content.sub(
      "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n",
      "## Links\n- [[61--demo|Bogus stale link]]\n"
    ))

    corrupted = doctor.check_intent_end("60")
    assert_equal "fail", find(corrupted, "intent_links_projection")[:status]

    clean = doctor.check_intent_end("61")
    assert_equal "pass", find(clean, "intent_links_projection")[:status],
                 "the sibling intent's own check must never leak the corrupted id's finding"
  end

  # --- intent_savepoint_truthful (WARN-only, intent 134) ------------------------

  # A duplicate (stage, milestone) pair is a phantom (Bridge.savepoint_phantom_lines) that
  # requires no lifecycle file to be absent, so it is the only phantom class that can appear
  # on an otherwise fully clean intent - the exact scenario the WARN-never-FAIL contract (D2/
  # D8, intent 134) needs to prove: every OTHER of the 5 checks stays "pass", so the overall
  # run_intent_check status is "warn", never "fail".
  def test_savepoint_truthful_warns_never_fails_on_duplicate_phantom_line
    dir = write_clean_intent(id: "45")
    File.write(File.join(dir, "savepoint.md"), <<~SP)
      2026-07-01T00:00:00Z  What  45--demo.md
      2026-07-01T00:01:00Z  Why  spec.md created
      2026-07-01T00:02:00Z  Why  spec.md created
    SP

    checks = doctor.check_intent_end("45")
    other_names = %w[intent_structure intent_lifecycle_artifacts intent_checklist_complete intent_links_projection]
    other_names.each { |name| assert_equal "pass", find(checks, name)[:status], "expected #{name} to stay clean" }

    savepoint_result = find(checks, "intent_savepoint_truthful")
    assert_equal "warn", savepoint_result[:status]
    refute_equal "fail", savepoint_result[:status]

    overall = doctor.run_intent_check("45")
    assert_equal "warn", overall[:status], "a savepoint-only phantom must never escalate the OVERALL verdict to fail"
  end

  # --- --intent / --store disambiguation ----------------------------------------

  def test_intent_ambiguous_across_stores_raises_naming_both
    write_clean_intent(id: "9", slug: "globaldemo", store_dir: global_store)
    proj_store = File.join(@home, "projects", "proj1", "store")
    FileUtils.mkdir_p(proj_store)
    write_clean_intent(id: "9", slug: "projdemo", store_dir: proj_store)

    d = doctor
    err = assert_raises(RuntimeError) { d.resolve_single_intent_dir("9") }
    assert_match(/ambiguous/i, err.message)
    assert_match(/global/, err.message)
    assert_match(/project:proj1/, err.message)

    global_dir, global_scope = d.resolve_single_intent_dir("9", store: "global")
    assert_equal "global", global_scope
    assert_match(%r{store/9--globaldemo\z}, global_dir)

    proj_dir, proj_scope = d.resolve_single_intent_dir("9", store: "project:proj1")
    assert_equal "project:proj1", proj_scope
    assert_match(%r{store/9--projdemo\z}, proj_dir)
  end

  # --- unresolvable id -----------------------------------------------------------

  def test_check_intent_end_fails_when_no_intent_dir_resolves
    checks = doctor.check_intent_end("999999")
    assert_equal 1, checks.size
    assert_equal "fail", checks.first[:status]
    assert_equal "intent_resolved", checks.first[:name]
  end
end
