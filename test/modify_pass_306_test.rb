# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/hook_registry"

# ModifyPass306Test (intent 306): the 44 MODIFY test files of cut-inventory
# 6b were walked once against the alpha tree after batches 1 and 2. This file
# pins what that pass corrected (stale fixture text and comments that narrated
# mechanisms removed in 2.0) and that no file the pass recorded as present
# disappears without a recorded decision. Static and hermetic: it reads the
# repo tree and asserts on text; it writes nothing.
class ModifyPass306Test < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  # The 42 files of cut-inventory 6b still present after 302 to 305
  # (savepoint_pre_hook_test and start_intent_test were deleted, on record).
  PRESENT = %w[
    plastic_core_budget_test plastic_md_batch0_conventions_test hook_registry_test install_hooks_test
    install_codex_hooks_test codex_hooks_test install_packaging_test codex_install_test
    codex_install_content_test installer_core_test install_sync_test installer_agent_models_test
    harness_support_docs_test harness_invocation_docs_test harness_text_test harness_adapters_doc_test
    session_start_test savepoint_ledger_test savepoint_phantom_test scaffold_intent_test end_intent_test
    end_intent_disarm_toctou_test end_intent_worktree_guard_test new_intent_test exec_worktree_test
    doctor_test doctor_core_test doctor_core_split_test doctor_revisions_remedy_test insights_test
    write_config_test dashboard_test spawn_preamble_test plastic_lock_cli_test lock_system_test
    roadmap_queue_test roadmap_savepoint_test qmd_sync_test skill_command_lint_test
    skill_rename_prune_test doctor_stray_skills_test auto_skill_contract_test update_verb_test
    rollback_verb_test creating_skills_scaffold_test
  ].freeze

  # Stale fixture text, comment wording, and test names the pass corrected,
  # per touched file. Every literal names something removed in 2.0 (intents
  # 302 and 304): a hook the fixtures called a gate, the S/M/L tier vocabulary,
  # the lock-gate, the curator agent, the fragment once called a gate, the
  # planner role used as an example author. None of these literals is on
  # gates_removed_test's or subtraction_304_test's removed-name lists (verified
  # in the 306 plan review, section D), so no removal note is needed here.
  CORRECTED = {
    "codex_hooks_test.rb" => ["not-a-real-gate", "hooks/<gate>", "run_hook(gate,"],
    "codex_install_test.rb" => ["hooks/<gate>"],
    "end_intent_test.rb" => ["Tier S"],
    "harness_text_test.rb" => ["lock-gate deny"],
    "new_intent_test.rb" => ["gate fire"],
    "dashboard_test.rb" => ["M tier"],
    "doctor_revisions_remedy_test.rb" => ["yields_curator", "names the curator"],
    "install_packaging_test.rb" => ["gate relocation"],
    "insights_test.rb" => ["planner"],
  }.freeze

  def test_every_recorded_6b_file_is_still_present
    missing = PRESENT.reject { |name| File.file?(File.join(ROOT, "test", "#{name}.rb")) }
    assert_empty missing,
      "6b files recorded as present by intent 306 are gone without a recorded decision: #{missing.join(', ')}"
  end

  def test_corrected_literals_do_not_return
    CORRECTED.each do |file, literals|
      body = File.read(File.join(ROOT, "test", file))
      literals.each do |literal|
        refute_includes body, literal,
          "#{file} carries the stale text #{literal.inspect} again (the mechanism it names was removed in 2.0)"
      end
    end
  end

  def test_doctor_report_sample_names_no_retired_launcher
    body = File.read(File.join(ROOT, "skills", "doctor", "report.md"))
    retired = HookRegistry::RETIRED_CLAUDE_LAUNCHERS.select { |name| body.include?(name) }
    assert_empty retired,
      "skills/doctor/report.md shows a retired launcher as sample output: #{retired.join(', ')}"
  end
end
