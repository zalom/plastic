# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/arm"
require_relative "../scripts/lib/index_entry"
require_relative "../scripts/lib/project_config"
require_relative "../scripts/lib/hook_registry"
require_relative "../scripts/lib/exec_worktree"

# Intent 302: the edit-path gates are gone. This file is the reverse-dependency
# acceptance test (spec D8): the removed files do not exist, the removed gate
# methods answer nowhere (the shared-helpers module that used to carry them was
# itself retired by intent 344), the kept helpers the plan review found inside
# the cut ranges still work on their new owners, the registry and the installer
# carry no gate, every script still parses and every lib still loads, and no
# live file references a removed name outside the retired-name list and the
# 2.0 removal notes.
class GatesRemovedTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  REMOVED_FILES = %w[
    scripts/lib/edit_gates.rb scripts/lib/codex_edit_gates.rb scripts/lib/links_gate.rb
    scripts/hook-edit-gates scripts/hook-bash-gate scripts/hook-code-gate scripts/hook-lock-gate
    scripts/hook-links-gate scripts/hook-create-gate scripts/hook-savepoint-pre
    hooks/edit-gates hooks/bash-gate
  ].freeze

  REMOVED_BRIDGE_METHODS = %i[
    check_gate code_gate_decision lock_gate_decision worktree_gate_decision holds_live_lock?
    gate_narration stage_label solo_delivery? solo_allow bash_gate_decision bash_write_targets
    bash_escape? non_owner_store_edit_reason parse_store_target
  ].freeze

  # Inside the cut ranges but still called by a live file (plan review A1, A2), or
  # called by hook-record.
  KEPT_BRIDGE_METHODS = %i[
    blank? index_entry_match intent_active? intent_id_from_dir deep_merge read_project_config skill_ref
  ].freeze

  # Names that may appear nowhere in the scanned roots except on a line that carries
  # the 2.0 removal note. Bare hook names (`edit-gates`, `lock-gate`) are not listed:
  # they live on in RETIRED_HOOK_NAMES and in purge fixtures on purpose.
  REMOVED_NAMES = %w[
    edit_gates codex_edit_gates links_gate.rb
    hook-edit-gates hook-bash-gate hook-code-gate hook-lock-gate hook-links-gate
    hook-create-gate hook-savepoint-pre
    check_gate code_gate_decision lock_gate_decision worktree_gate_decision holds_live_lock?
    gate_narration solo_delivery? bash_gate_decision bash_write_targets claim_gate_reason
    GATE_TOOLS CODEX_PRE_HOOKS CODEX_BASH_HOOKS
    claude_hooks_implemented claude_dispatcher_gate_names EditGates LinksGate
    EXIT_PRECONDITION PROBE_FILENAME ADVISORY_LINE
  ].freeze

  SCAN_ROOTS = %w[scripts hooks test docs/reference docs/architecture.md docs/internals.md].freeze
  REMOVAL_NOTE = /removed in 2\.0|retired in 2\.0|left with the gates/.freeze

  def test_removed_files_are_gone
    present = REMOVED_FILES.select { |rel| File.exist?(File.join(REPO, rel)) }
    assert_empty present, "still on disk: #{present.inspect}"
  end

  def test_bridge_no_longer_responds_to_the_gate_methods
    refute Object.const_defined?(:Bridge), "the shared-helpers module must be fully retired (intent 344)"
  end

  def test_bridge_still_responds_to_the_kept_methods
    assert Arm.respond_to?(:blank?)
    assert IndexEntry.respond_to?(:match)
    assert IndexEntry.respond_to?(:active?)
    assert Arm.respond_to?(:intent_id_for)
    assert ProjectConfig.respond_to?(:deep_merge)
    assert ProjectConfig.respond_to?(:read)
    assert Lock.respond_to?(:skill_ref)
  end

  def test_deep_merge_and_intent_id_from_dir_survive_the_cut
    merged = ProjectConfig.deep_merge({ "a" => 1, "n" => { "x" => 1 } }, { "n" => { "y" => 2 } })
    assert_equal({ "a" => 1, "n" => { "x" => 1, "y" => 2 } }, merged)
    assert_equal "96", Arm.intent_id_for("/s/store/96--demo")
    assert_equal "nodash", Arm.intent_id_for("/s/store/nodash")
  end

  def test_read_project_config_returns_merged_defaults_after_the_cut
    Dir.mktmpdir("gates-removed-home") do |home|
      prev = ENV["HOME"]
      ENV["HOME"] = home
      begin
        config = ProjectConfig.read("no-such-project")
        assert_equal ["AGENTS.md"], config["governing_docs"]
        assert_equal "commit", config.dig("release", "on_complete")
      ensure
        ENV["HOME"] = prev
      end
    end
  end

  def test_claim_gate_reason_is_gone_and_fail_open_stays
    refute Claim.respond_to?(:claim_gate_reason)
    assert Claim.respond_to?(:fail_open?)
  end

  # Intent 355, n2 registers one legitimate PreToolUse hook (call-budget, a
  # per-attempt call COUNT, never a content deny) after intent 302 removed
  # the edit-path gates. This test now proves the gate TABLES stayed gone
  # and that the one PreToolUse entry is call-budget alone, never a revived
  # edit-gates or bash-gate.
  def test_registry_carries_no_gate_tables_and_only_call_budget_under_pretooluse
    names = HookRegistry.events["PreToolUse"].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    assert_equal ["call-budget"], names
    %i[GATE_TOOLS CODEX_GATE_TOOLS CODEX_PRE_HOOKS CODEX_BASH_HOOKS].each do |c|
      refute HookRegistry.const_defined?(c), "HookRegistry::#{c} must be gone"
    end
    raw = JSON.parse(File.read(File.join(REPO, "hooks", "hooks.json")))
    json_names = raw["hooks"]["PreToolUse"].flat_map { |g| g["hooks"].map { |h| h["command"][/run-hook" ([a-z-]+)/, 1] } }
    assert_equal ["call-budget"], json_names, "hooks/hooks.json PreToolUse must carry call-budget alone"
  end

  def test_exec_worktree_has_no_precondition_seam
    %i[EXIT_PRECONDITION PROBE_FILENAME ADVISORY_LINE].each do |c|
      refute ExecWorktree.const_defined?(c), "ExecWorktree::#{c} must be gone"
    end
    refute_includes ExecWorktree.method(:run).parameters, [:key, :gate]
  end

  # The installer manifest is a literal hash of "src" => "dst" pairs in installer_core.rb.
  # Every scripts/ entry must exist on disk, and none may name a removed file.
  def test_installer_manifest_lists_no_removed_file_and_every_entry_exists
    src = File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))
    entries = src.scan(/^\s*"(scripts\/[^"]+)"\s*=>\s*"scripts\/[^"]+",?\s*$/).flatten.uniq
    refute_empty entries
    removed = entries & REMOVED_FILES
    assert_empty removed, "manifest still lists #{removed.inspect}"
    missing = entries.reject { |rel| File.exist?(File.join(REPO, rel)) }
    assert_empty missing, "manifest lists files that do not exist: #{missing.inspect}"
  end

  def test_every_ruby_script_parses_and_every_lib_loads
    Dir.mktmpdir("gates-removed-tmp") do |tmp|
      env = { "RUBYOPT" => nil, "PLASTIC_TMP" => tmp, "CLAUDE_CODE_SESSION_ID" => nil }
      scripts = Dir[File.join(REPO, "scripts", "*")].select { |f| File.file?(f) }
      ruby_scripts = scripts.select { |f| File.open(f, &:readline).to_s.include?("ruby") rescue false }
      ruby_scripts.each do |f|
        _out, err, status = Open3.capture3(env, RbConfig.ruby, "-c", f)
        assert status.success?, "#{f} does not parse: #{err}"
      end
      Dir[File.join(REPO, "scripts", "lib", "*.rb")].sort.each do |lib|
        _out, err, status = Open3.capture3(env, RbConfig.ruby, "-e", "require #{lib.inspect}")
        assert status.success?, "#{File.basename(lib)} does not load: #{err.lines.first}"
      end
    end
  end

  def test_no_live_reference_to_a_removed_name_outside_the_removal_notes
    offenders = []
    scan_files.each do |path|
      File.foreach(path).with_index(1) do |line, n|
        next if line =~ REMOVAL_NOTE
        hit = REMOVED_NAMES.find { |name| line.include?(name) }
        offenders << "#{path.sub("#{REPO}/", "")}:#{n}: #{hit}" if hit
      end
    end
    assert_empty offenders, "removed names still referenced:\n#{offenders.first(40).join("\n")}"
  end

  private

  def scan_files
    # Intent 342 (G9): test/fixtures/legacy_intents/ and test/fixtures/dogfood_intent/
    # are frozen copies of historical intent records, not shipped tree; the scanner
    # polices what ships, not history quoted verbatim in a fixture (spec.md D15).
    SCAN_ROOTS.flat_map do |root|
      abs = File.join(REPO, root)
      File.directory?(abs) ? Dir[File.join(abs, "**", "*")].select { |f| File.file?(f) } : [abs]
    end.reject { |f| f == File.expand_path(__FILE__) }
       .reject { |f| f.start_with?(File.join(REPO, "test/fixtures/legacy_intents/")) || f.start_with?(File.join(REPO, "test/fixtures/dogfood_intent/")) }
  end
end
