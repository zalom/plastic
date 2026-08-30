# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/arm"

# AutoCore307Test (intent 307): auto mode runs on the new core. The /tmp
# bridge JSON is gone (ruling 6 of intent 296: the session pointer plus
# delivery.lock is the whole bridge), `Arm` is how a team takes and gives
# back an intent, and the auto documents describe the ruled two-boot shape:
# the lead writes the plan and a failure-mode matrix, one adversarial plan
# reviewer reads them before code, one executor builds tests first, a light
# post-execution review by risk, the full suite once. Static and hermetic.
class AutoCore307Test < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  KEPT_BRIDGE = %i[blank? index_entry_match intent_active? intent_id_from_dir deep_merge
                   read_project_config skill_ref].freeze
  REMOVED_BRIDGE = %i[tmp_dir path bridge_intent_dir lock_cache derive_key resolve_session
                      bridge_valid? bridge_cwd_tier enclosing_worktree_dir discover_bridge
                      purge_done_bridges read write derive_data derive arm arm_auto arm_guided
                      sole_bridge_data disarm_auto repair_lock].freeze
  ARM_API = %i[arm disarm worktree_block repair resolve_session bridge_hash intent_dir_from_pointer
               read_pointer write_pointer reset_pointer derive_key].freeze

  # Every caller that names a removed Bridge method must carry the 2.0 note on
  # the same line (the docs under docs/ are not scanned: their bridge sections
  # carry one note at the head, spec Non-Goals).
  SCAN_ROOTS = %w[scripts hooks skills agents templates PLASTIC.md README.md].freeze
  REMOVED_CALLS = /Bridge\.(arm_auto|arm_guided|derive|discover_bridge|disarm_auto|repair_lock|read|write|purge_done_bridges|bridge_intent_dir|resolve_session|derive_key)\b/.freeze
  REMOVAL_NOTE = /removed in 2\.0|retired in 2\.0|left with the gates/.freeze

  def read(rel)
    File.read(File.join(ROOT, rel))
  end

  def scan_files(roots)
    roots.flat_map do |r|
      p = File.join(ROOT, r)
      File.file?(p) ? [p] : Dir[File.join(p, "**", "*")].select { |f| File.file?(f) }
    end
  end

  # --- the bridge is gone --------------------------------------------------------

  def test_bridge_keeps_exactly_the_seven_helpers
    KEPT_BRIDGE.each { |m| assert Bridge.respond_to?(m), "Bridge.#{m} must stay" }
    REMOVED_BRIDGE.each { |m| refute Bridge.respond_to?(m), "Bridge.#{m} was removed in 2.0 (intent 307)" }
    refute Bridge.const_defined?(:LockHeldError), "LockHeldError was removed in 2.0 (intent 307)"
  end

  def test_arm_carries_the_api
    ARM_API.each { |m| assert Arm.respond_to?(m), "Arm.#{m} must exist" }
  end

  def test_no_caller_names_a_removed_bridge_method
    offenders = []
    scan_files(SCAN_ROOTS).each do |path|
      next if path.end_with?("bridge.rb")
      File.read(path).each_line.with_index(1) do |line, n|
        next unless line.match?(REMOVED_CALLS)
        next if line.match?(REMOVAL_NOTE)
        offenders << "#{path.sub("#{ROOT}/", '')}:#{n}"
      end
    end
    assert_empty offenders, "removed Bridge methods still called: #{offenders.join(', ')}"
  end

  def test_no_bridge_test_file_remains
    assert_empty Dir[File.join(ROOT, "test", "bridge_*_test.rb")].map { |f| File.basename(f) }
  end

  def test_plastic_lock_usage_names_arm
    src = read("scripts/plastic-lock")
    assert_match(/VERBS = %w\[arm\b/, src)
    assert_includes src, "# Usage: plastic-lock <arm|"
    refute_includes src, "Bridge.discover_bridge"
  end

  # The two pure helpers the deleted purge test pinned (bridge_purge_test.rb).
  def test_index_entry_match_accepts_em_dash_and_plain_hyphen
    assert Bridge.index_entry_match("- [96 — demo](store/96--demo/96--demo.md) — note")
    assert Bridge.index_entry_match("- [96 - demo](store/96--demo/96--demo.md) - note")
    refute Bridge.index_entry_match("- plain bullet")
  end

  # The six assertions the deleted bridge_purge_test pinned on the two INDEX
  # helpers, ported whole (review B2).
  def test_intent_active_reads_the_index_active_section
    Dir.mktmpdir("auto-core-307") do |home|
      store = File.join(home, ".plastic", "projects", "x", "store")
      FileUtils.mkdir_p(store)
      refute Bridge.intent_active?("96", store: store), "no INDEX.md means not active"
      File.write(File.join(File.dirname(store), "INDEX.md"),
                 "## Active\n- [96 — demo](store/96--demo/96--demo.md)\n- [98 - hyphen](store/98--h/98--h.md)\n\n## Future\n- [97 — x](store/97--x/97--x.md)\n")
      assert Bridge.intent_active?("96", store: store)
      assert Bridge.intent_active?("98", store: store), "a plain-hyphen separator reads as active"
      refute Bridge.intent_active?("97", store: store), "an id under Future is not active"
      assert Bridge.intent_active?("5", store: store, index_active_ids: %w[5 6]), "the pure-data seam"
      refute Bridge.intent_active?("7", store: store, index_active_ids: %w[5 6])
    end
  end

  # --- the auto shape ----------------------------------------------------------

  def test_auto_skill_takes_the_intent_through_plastic_lock_arm
    body = read("skills/auto/SKILL.md")
    assert_includes body, "plastic-lock arm"
    assert_includes body, "plan-reviewer-prompt.md"
    refute_includes body, "Lifecycle Gate"
    refute_includes body, "two-stage review" # removed in 2.0 (intent 307)
    refute_includes body, "M and L only"
    refute_includes body, "Bridge." + "arm_auto" # split so the hermeticity scanners see no arm call here
    refute_match(/\bat L\b/, body) # removed in 2.0 (intent 304)
    assert File.file?(File.join(ROOT, "skills", "intent-executing", "plan-reviewer-prompt.md"))
  end

  def test_plan_reviewer_prompt_reviews_the_matrix_before_code
    body = read("skills/intent-executing/plan-reviewer-prompt.md")
    assert_includes body, "failure-mode matrix"
    assert_match(/before any code/i, body)
    assert_match(/verdict/i, body)
  end

  def test_enforcer_and_executor_carry_no_gate_or_tier_grammar
    %w[agents/plastic-enforcer.md agents/plastic-executor.md].each do |rel|
      body = read(rel)
      body.each_line.with_index(1) do |line, n|
        next if line.match?(REMOVAL_NOTE)
        refute_match(/\bgates?\b/i, line, "#{rel}:#{n} still speaks of a gate")
      end
      refute_includes body, "S/M", "#{rel} carries S/M tier grammar" # removed in 2.0 (intent 304)
      refute_match(/\bat L\b/, body) # removed in 2.0 (intent 304)
      refute_match(/\bplanner\b/, body, "#{rel} names the planner, an agent removed in 2.0 (intent 304)")
    end
  end

  def test_intent_executing_keeps_the_executor_codes_and_drops_the_per_task_loop
    body = read("skills/intent-executing/SKILL.md")
    assert_includes body, "NEEDS_CONTEXT"
    assert_includes body, "BLOCKED"
    refute_includes body, "Several independent actions: one subagent per task"
    refute_includes body, "two-stage review" # removed in 2.0 (intent 307)
  end

  def test_spawn_preamble_exemplar_names_the_executor_not_the_planner
    src = read("scripts/spawn-preamble")
    refute_match(/\bplanner\b/, src)
    assert_includes src, "the executor reports what was built and the test result"
  end

  def test_capture_hook_auto_message_promises_no_gate
    src = read("scripts/hook-capture")
    refute_includes src, "lifecycle gate"
    assert_includes src, "Auto-mode request detected"
  end

  def test_subtraction_scan_sees_slash_tier_grammar
    src = read("test/subtraction_304_test.rb")
    assert_includes src, "S/M", "the 304 tier scan must cover the S/M spelling (review A5 of intent 306)" # removed in 2.0 (intent 304)
  end

  def test_plastic_md_names_the_pointer_and_lock_not_the_bridge
    body = read("PLASTIC.md")
    refute_includes body, "arm_auto"
    refute_includes body, "Lifecycle Gate"
    refute_match(%r{/tmp.*bridge}i, body)
    assert_includes body, "current (the pointer)"
  end
end
