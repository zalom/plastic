# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/arm"
require_relative "../scripts/lib/session_ledger"
require_relative "../scripts/lib/index_entry"

# AutoCore307Test (intent 307): auto mode runs on the new core. The /tmp
# bridge JSON is gone (ruling 6 of intent 296: the session pointer plus
# delivery.lock is the whole bridge), `Arm` is how a team takes and gives
# back an intent, and the auto documents describe the ruled two-boot shape:
# the lead writes the plan and a failure-mode matrix, one adversarial plan
# reviewer reads them before code, one executor builds tests first, a light
# post-execution review by risk, the full suite once. Static and hermetic.
class AutoCore307Test < Minitest::Test
  # Intent 363 emptied PLASTIC.md of doctrine. It is now a one-page pointer at the
  # `plastic` command line (ruling D43), so the content pins that used to live here
  # were deleted rather than rewritten. The doctrine they guarded is still in the
  # conventions skill and its reference chapters, which Batch 2 rehomes into the
  # commands that need it.

  ROOT = File.expand_path("..", __dir__)

  KEPT_BRIDGE = %i[blank? index_entry_match intent_active? intent_id_from_dir deep_merge
                   read_project_config skill_ref].freeze
  REMOVED_BRIDGE = %i[tmp_dir path bridge_intent_dir lock_cache derive_key resolve_session
                      bridge_valid? bridge_cwd_tier enclosing_worktree_dir discover_bridge
                      purge_done_bridges read write derive_data derive arm arm_auto arm_guided
                      sole_bridge_data disarm_auto repair_lock].freeze
  ARM_API = %i[arm disarm worktree_block repair resolve_session delivery derive_key].freeze
  REMOVED_POINTER_API = %i[pointer_path read_pointer write_pointer reset_pointer
                           preexisting_pointer? intent_dir_from_pointer].freeze

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
    refute Object.const_defined?(:Bridge), "the shared-helpers module was fully retired (intent 344)"
  end

  def test_arm_carries_the_api
    ARM_API.each { |m| assert Arm.respond_to?(m), "Arm.#{m} must exist" }
  end

  def test_arm_api_has_no_pointer_methods
    REMOVED_POINTER_API.each { |m| refute Arm.respond_to?(m), "Arm.#{m} must be gone (344 n4)" }
    refute SessionLedger.respond_to?(:pointer_path), "SessionLedger.pointer_path must be gone (344 n4)"
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
    leftover = Dir[File.join(ROOT, "test", "bridge_*_test.rb")]
                 .map { |f| File.basename(f) }
                 .reject { |f| f == "bridge_retired_test.rb" }
    assert_empty leftover
  end

  def test_plastic_lock_usage_names_arm
    src = read("scripts/plastic-lock")
    assert_match(/VERBS = %w\[arm\b/, src)
    assert_includes src, "# Usage: plastic-lock <arm|"
    refute_includes src, "Bridge.discover_bridge"
  end

  # The two pure helpers the deleted purge test pinned (bridge_purge_test.rb).
  def test_index_entry_match_accepts_em_dash_and_plain_hyphen
    assert IndexEntry.match("- [96 — demo](store/96--demo/96--demo.md) — note")
    assert IndexEntry.match("- [96 - demo](store/96--demo/96--demo.md) - note")
    refute IndexEntry.match("- plain bullet")
  end

  # The six assertions the deleted bridge_purge_test pinned on the two INDEX
  # helpers, ported whole (review B2).
  def test_intent_active_reads_the_index_active_section
    Dir.mktmpdir("auto-core-307") do |home|
      store = File.join(home, ".plastic", "projects", "x", "store")
      FileUtils.mkdir_p(store)
      refute IndexEntry.active?("96", store: store), "no INDEX.md means not active"
      File.write(File.join(File.dirname(store), "INDEX.md"),
                 "## Active\n- [96 — demo](store/96--demo/96--demo.md)\n- [98 - hyphen](store/98--h/98--h.md)\n\n## Future\n- [97 — x](store/97--x/97--x.md)\n")
      assert IndexEntry.active?("96", store: store)
      assert IndexEntry.active?("98", store: store), "a plain-hyphen separator reads as active"
      refute IndexEntry.active?("97", store: store), "an id under Future is not active"
      assert IndexEntry.active?("5", store: store, index_active_ids: %w[5 6]), "the pure-data seam"
      refute IndexEntry.active?("7", store: store, index_active_ids: %w[5 6])
    end
  end

  # --- the auto shape ----------------------------------------------------------

  # test_auto_skill_takes_the_intent_through_plastic_lock_arm was retired by intent 372
  # (family 5): skills/auto/SKILL.md is gone. The arming call it pinned is now
  # test/cli/auto_session_commands_test.rb's test_take_runs_plastic_lock_arm, which asserts
  # the same "arm --intent-dir ... --mode auto" call against the real `AutoTake` command.

  # test_plan_reviewer_prompt_reviews_the_matrix_before_code was retired by intent 372
  # (family 2): skills/intent-executing/plan-reviewer-prompt.md is gone; the reviewer
  # step it described is now `plastic intent step`, a command, not skill prose.

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

  # test_intent_executing_keeps_the_executor_codes_and_drops_the_per_task_loop was retired
  # by intent 372 (family 2): skills/intent-executing/SKILL.md is gone, moved into the
  # `plastic intent step` command.

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
end
