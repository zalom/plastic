# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/outcome_guard"

# Intent 222 - doctor's fourth check scope, `--intent <id>`, verifies ONE intent's structure
# at the moment it is about to close: intent-file validity, lifecycle-artifact presence,
# checklist completeness, ## Links projection, savepoint truthfulness, and (intent 329) a
# lagging checklist tick. Four FAIL-severity checks plus two WARN-only
# (intent_savepoint_truthful, per intent 134's binding advisory-only ruling; and
# intent_ticks_lag, per intent 329's ruling that a lagging tick warns rather than blocks) -
# see the WARN-not-FAIL tests below. Hermetic: own Dir.mktmpdir store, no ambient session, no
# eval, no ENV/global-constant seam.
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
    File.write(File.join(dir, "spec.md"), "# Spec: Demo intent #{id}\n")
    File.write(File.join(dir, "plan.md"), "# Plan: Demo intent #{id}\n\n- [x] Step 1\n")
    File.write(File.join(dir, "checklist.md"), "# Checklist: Demo intent #{id}\n\n- [x] Step 1\n")
    File.write(File.join(dir, "outcome.md"),
               "---\ndisposition: delivered\n---\n# Outcome: Demo intent #{id}\n\n## Summary\nDid it.\n")
    File.write(File.join(dir, "savepoint.md"), "2026-07-01T00:00:00Z  What  #{id}--#{slug}.md\n")
    dir
  end

  def find(checks, name) = checks.find { |c| c[:name] == name }

  # INDEX.md for one store root, in the shape index_sections_by_dir parses: a `## Section`
  # heading followed by lines carrying a `store/<dirname>/...` reference.
  # sections: { "Completed" => ["45--demo"], "Active" => [...] }
  def write_index(sections, root: @home)
    body = +"# Index\n\n"
    sections.each do |name, dirnames|
      body << "## #{name}\n"
      dirnames.each { |d| body << "- [#{d}](store/#{d}/#{d}.md)\n" }
      body << "\n"
    end
    File.write(File.join(root, "INDEX.md"), body)
  end

  # The store's doctor-exclusions table, sibling to that store's INDEX.md (274 D6).
  def write_exclusions(lines, root: @home)
    File.write(File.join(root, "doctor-exclusions"), lines.join("\n") + "\n")
  end

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
    assert_equal 6, checks.size
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

  # A duplicate (stage, milestone) pair is a phantom (Savepoint.savepoint_phantom_lines) that
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

  # --- intent_savepoint_truthful: doctor-exclusions honored (intent 281) --------

  # The coverage this file lacked before intent 281: a plain missing savepoint.md with no
  # INDEX and no exclusions file must still warn exactly as it always has. This is the
  # baseline the excluded/registered cases below are measured against.
  def test_savepoint_truthful_warns_when_savepoint_is_missing_entirely
    dir = write_clean_intent(id: "50")
    File.delete(File.join(dir, "savepoint.md"))

    checks = doctor.check_intent_end("50")
    result = find(checks, "intent_savepoint_truthful")
    assert_equal "warn", result[:status]
    assert_equal "savepoint.md is missing", result[:message]
    assert_empty result[:details].to_a
  end

  # A terminal intent whose id is registered under savepoint_operational (281 D1) reaches
  # pass, with the honest count and the exclusions path folded into the message (274 D4's
  # wording) and nothing in details.
  def test_missing_savepoint_is_excluded_for_a_terminal_registered_intent
    dir = write_clean_intent(id: "51")
    File.delete(File.join(dir, "savepoint.md"))
    write_index({ "Completed" => ["51--demo"] })
    write_exclusions(["savepoint_operational 51"])

    checks = doctor.check_intent_end("51")
    result = find(checks, "intent_savepoint_truthful")
    assert_equal "pass", result[:status]
    assert_match(/1 excluded via/, result[:message])
    assert_match(/doctor-exclusions/, result[:message])
    assert_empty result[:details].to_a
  end

  # Precision pin, the per-intent mirror of doctor_done_signals_test.rb's case 11: a
  # registration naming a DIFFERENT id must never suppress this intent's own warning. Proves
  # the fix keys on the id, not on the mere existence of the exclusions file.
  def test_missing_savepoint_still_warns_when_another_intent_is_registered
    dir = write_clean_intent(id: "52")
    File.delete(File.join(dir, "savepoint.md"))
    write_index({ "Completed" => ["52--demo"] })
    write_exclusions(["savepoint_operational 99"])

    checks = doctor.check_intent_end("52")
    result = find(checks, "intent_savepoint_truthful")
    assert_equal "warn", result[:status]
    assert_equal "savepoint.md is missing", result[:message]
  end

  # 281 D3: the exclusion is honored only when the intent is terminal in its store's INDEX.
  # A still-Active intent's missing-savepoint warning must never be silenced by a
  # registration, because scripts/end-intent's pre-write gate runs against exactly this
  # state and its warning must stay live and repairable.
  def test_missing_savepoint_still_warns_for_a_non_terminal_intent
    dir = write_clean_intent(id: "53")
    File.delete(File.join(dir, "savepoint.md"))
    write_index({ "Active" => ["53--demo"] })
    write_exclusions(["savepoint_operational 53"])

    checks = doctor.check_intent_end("53")
    result = find(checks, "intent_savepoint_truthful")
    assert_equal "warn", result[:status]
  end

  # Intent 211, 281 D2: the phantom-line branch is permanently non-suppressible by id or
  # scope, even for an intent excluded and terminal. Pins a standing ruling against a future
  # "just exclude the whole check" edit.
  def test_phantom_line_still_warns_for_an_excluded_terminal_intent
    dir = write_clean_intent(id: "54")
    File.write(File.join(dir, "savepoint.md"), <<~SP)
      2026-07-01T00:00:00Z  What  54--demo.md
      2026-07-01T00:01:00Z  Why  spec.md created
      2026-07-01T00:02:00Z  Why  spec.md created
    SP
    write_index({ "Completed" => ["54--demo"] })
    write_exclusions(["savepoint_operational 54"])

    checks = doctor.check_intent_end("54")
    result = find(checks, "intent_savepoint_truthful")
    assert_equal "warn", result[:status]
    assert(result[:details].any? { |d| d =~ /phantom/ }, "expected a phantom-line detail, got #{result[:details].inspect}")
  end

  # 281 D5: a malformed line never suppresses anything, even when a valid registration for
  # this same id sits in the same file. Loud on the branch that consulted the file: the
  # parse error lands in details and the exclusions path is named in fix_hint.
  def test_malformed_exclusion_line_never_suppresses_and_is_loud
    dir = write_clean_intent(id: "55")
    File.delete(File.join(dir, "savepoint.md"))
    write_index({ "Completed" => ["55--demo"] })
    write_exclusions(["savepoint_operational 55", "bogus_rule 55"])

    checks = doctor.check_intent_end("55")
    result = find(checks, "intent_savepoint_truthful")
    assert_equal "warn", result[:status]
    refute_empty result[:details].to_a
    assert(result[:details].any? { |d| d =~ /line 2/ }, "expected a line-2 parse error, got #{result[:details].inspect}")
    assert_match(/doctor-exclusions/, result[:fix_hint].to_s)
  end

  # Scope threading: check_intent_end must resolve the INTENT'S OWN project store's INDEX and
  # exclusions, not the global store's, even when the global store has no matching state at
  # all. The only case that proves the fix threads the correct store key through.
  def test_exclusions_are_read_from_the_intents_own_project_store
    proj_root = File.join(@home, "projects", "proj1")
    proj_store = File.join(proj_root, "store")
    FileUtils.mkdir_p(proj_store)
    write_clean_intent(id: "56", slug: "projdemo", store_dir: proj_store)
    File.delete(File.join(proj_store, "56--projdemo", "savepoint.md"))
    write_index({ "Completed" => ["56--projdemo"] }, root: proj_root)
    write_exclusions(["savepoint_operational 56"], root: proj_root)

    checks = doctor.check_intent_end("56")
    result = find(checks, "intent_savepoint_truthful")
    assert_equal "pass", result[:status]
  end

  # --- intent_ticks_lag (WARN-only, intent 329) ---------------------------------

  # V1: the exact case the ruling named - commits recorded, nothing ticked.
  def test_ticks_lag_warns_with_commits_recorded_and_no_ticks
    dir = write_clean_intent(id: "70")
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n- [ ] Step 1\n- [ ] Step 2\n")
    File.write(File.join(dir, "savepoint.md"), <<~SP)
      2026-07-01T00:00:00Z  What  70--demo.md
      2026-07-01T00:05:00Z  Commit  abc123 landed step 1
    SP

    checks = doctor.check_intent_end("70")
    result = find(checks, "intent_ticks_lag")
    assert_equal "warn", result[:status]
    assert_match(/ticks lag the branch/, result[:message])
  end

  # V2: a delivery that ticked as it went must never warn, even with commits recorded.
  def test_ticks_lag_passes_when_items_are_ticked
    dir = write_clean_intent(id: "71")
    File.write(File.join(dir, "savepoint.md"), <<~SP)
      2026-07-01T00:00:00Z  What  71--demo.md
      2026-07-01T00:05:00Z  Commit  abc123 landed step 1
    SP

    checks = doctor.check_intent_end("71")
    result = find(checks, "intent_ticks_lag")
    assert_equal "pass", result[:status]
  end

  # V3: a freshly armed intent, no commit yet, must not warn even though nothing is ticked.
  def test_ticks_lag_passes_with_no_commit_lines
    dir = write_clean_intent(id: "72")
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n- [ ] Step 1\n")

    checks = doctor.check_intent_end("72")
    result = find(checks, "intent_ticks_lag")
    assert_equal "pass", result[:status]
  end

  # V4: a checklist with no items to tick is the skip condition, not zero ticks, regardless
  # of commits. Four shapes count as "no items" (IntentScreen.checklist_items returns []
  # for all of them): the file is absent, it carries only the placeholder sentinel, it is
  # empty, or it has prose but no `- [ ]` line at all.
  def test_ticks_lag_skips_a_checklist_with_no_items
    {
      "73" => ->(dir) { File.delete(File.join(dir, "checklist.md")) },
      "73p" => ->(dir) { File.write(File.join(dir, "checklist.md"), "#{IntentScreen::PLACEHOLDER_SENTINEL}\n") },
      "73e" => ->(dir) { File.write(File.join(dir, "checklist.md"), "") },
      "73i" => ->(dir) { File.write(File.join(dir, "checklist.md"), "# Checklist\n\nNo items yet.\n") },
    }.each do |id, mutate_checklist|
      dir = write_clean_intent(id: id)
      mutate_checklist.call(dir)
      File.write(File.join(dir, "savepoint.md"), <<~SP)
        2026-07-01T00:00:00Z  What  #{id}--demo.md
        2026-07-01T00:05:00Z  Commit  abc123 landed
      SP

      checks = doctor.check_intent_end(id)
      result = find(checks, "intent_ticks_lag")
      assert_equal "pass", result[:status], "expected the #{id.inspect} shape to pass"
      assert_match(%r{n/a}, result[:message], "expected the #{id.inspect} shape to report n/a")
    end
  end

  # V5: WARN, never FAIL, and the overall rollup must never escalate past warn on this
  # check's account. An indented, unchecked sub-item is the one shape that lets every OTHER
  # check stay clean while ticks_lag fires: intent_checklist_complete's own regex requires no
  # leading whitespace, so it never sees this line, while IntentScreen::ITEM_RE (which
  # ticks_lag reuses) does.
  def test_ticks_lag_is_warn_never_fail
    dir = write_clean_intent(id: "74")
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n  - [ ] Sub-item never checked\n")
    File.write(File.join(dir, "savepoint.md"), <<~SP)
      2026-07-01T00:00:00Z  What  74--demo.md
      2026-07-01T00:05:00Z  Commit  abc123 landed
    SP

    checks = doctor.check_intent_end("74")
    other_names = %w[intent_structure intent_lifecycle_artifacts intent_checklist_complete
                      intent_links_projection intent_savepoint_truthful]
    other_names.each { |name| assert_equal "pass", find(checks, name)[:status], "expected #{name} to stay clean" }

    result = find(checks, "intent_ticks_lag")
    assert_equal "warn", result[:status]

    overall = doctor.run_intent_check("74")
    assert_equal "warn", overall[:status]
  end

  # V6: only `Commit`-kind lines count; `Review`, `Lock`, and malformed lines never do, even
  # when the word "Commit" appears inside a `Review` line's own text, the shape most likely
  # to miscount a naive substring search.
  def test_ticks_lag_counts_only_commit_kind_lines
    dir = write_clean_intent(id: "75")
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n- [ ] Step 1\n")
    File.write(File.join(dir, "savepoint.md"), <<~SP)
      2026-07-01T00:00:00Z  What  75--demo.md
      2026-07-01T00:05:00Z  Review  Commit abc123 was reviewed
      2026-07-01T00:06:00Z  Lock  takeover: session xyz
      not a valid savepoint line at all
    SP

    checks = doctor.check_intent_end("75")
    result = find(checks, "intent_ticks_lag")
    assert_equal "pass", result[:status]
    assert_match(/0 commit\(s\) recorded/, result[:message])
  end

  # V7: an indented `  - [x]` sub-item must count the same way it counts for the Progress
  # bar (both go through IntentScreen.checklist_items), or the two surfaces contradict.
  def test_ticks_lag_agrees_with_the_progress_bar_on_indented_items
    dir = write_clean_intent(id: "76")
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n  - [x] Indented sub-item, ticked\n")
    File.write(File.join(dir, "savepoint.md"), <<~SP)
      2026-07-01T00:00:00Z  What  76--demo.md
      2026-07-01T00:05:00Z  Commit  abc123 landed
    SP

    checks = doctor.check_intent_end("76")
    result = find(checks, "intent_ticks_lag")
    assert_equal "pass", result[:status]
    assert_match(/1 of 1 ticked/, result[:message])
  end

  # V9: a missing savepoint.md counts as zero commits, never a raise.
  def test_ticks_lag_treats_a_missing_savepoint_as_no_commits
    dir = write_clean_intent(id: "77")
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n- [ ] Step 1\n")
    File.delete(File.join(dir, "savepoint.md"))

    checks = doctor.check_intent_end("77")
    result = find(checks, "intent_ticks_lag")
    assert_equal "pass", result[:status]
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
