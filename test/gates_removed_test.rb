# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/hook_registry"
require_relative "../scripts/lib/exec_worktree"

# Intent 302: the edit-path gates are gone. This file is the reverse-dependency
# acceptance test (spec D8): the removed files do not exist, the removed Bridge
# methods do not respond, the kept methods the plan review found inside the cut
# ranges still work, the registry and the installer carry no gate, every script
# still parses and every lib still loads, and no live file references a removed
# name outside the retired-name list and the 2.0 removal notes.
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
  # called by start_intent.rb and hook-record.
  KEPT_BRIDGE_METHODS = %i[
    deep_merge intent_id_from_dir read_project_config has_real_action? intent_active?
    intent_dir_for append_savepoint append_exec_started
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
    left = REMOVED_BRIDGE_METHODS.select { |m| Bridge.respond_to?(m) }
    assert_empty left, "Bridge still responds to #{left.inspect}"
    %i[STAGE_LABELS NEXT_HINTS PLASTIC_OK_RE].each do |c|
      refute Bridge.const_defined?(c), "Bridge::#{c} only served the gates"
    end
  end

  def test_bridge_still_responds_to_the_kept_methods
    missing = KEPT_BRIDGE_METHODS.reject { |m| Bridge.respond_to?(m) }
    assert_empty missing, "Bridge lost #{missing.inspect}"
  end

  def test_deep_merge_and_intent_id_from_dir_survive_the_cut
    merged = Bridge.deep_merge({ "a" => 1, "n" => { "x" => 1 } }, { "n" => { "y" => 2 } })
    assert_equal({ "a" => 1, "n" => { "x" => 1, "y" => 2 } }, merged)
    assert_equal "96", Bridge.intent_id_from_dir("/s/store/96--demo")
    assert_nil Bridge.intent_id_from_dir("/s/store/nodash")
  end

  def test_read_project_config_returns_merged_defaults_after_the_cut
    Dir.mktmpdir("gates-removed-home") do |home|
      prev = ENV["HOME"]
      ENV["HOME"] = home
      begin
        config = Bridge.read_project_config("no-such-project")
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

  def test_registry_carries_no_pre_tool_use_and_no_gate_tables
    refute HookRegistry.events.key?("PreToolUse")
    %i[GATE_TOOLS CODEX_GATE_TOOLS CODEX_PRE_HOOKS CODEX_BASH_HOOKS].each do |c|
      refute HookRegistry.const_defined?(c), "HookRegistry::#{c} must be gone"
    end
    raw = JSON.parse(File.read(File.join(REPO, "hooks", "hooks.json")))
    refute raw["hooks"].key?("PreToolUse"), "hooks/hooks.json still registers PreToolUse"
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
    SCAN_ROOTS.flat_map do |root|
      abs = File.join(REPO, root)
      File.directory?(abs) ? Dir[File.join(abs, "**", "*")].select { |f| File.file?(f) } : [abs]
    end.reject { |f| f == File.expand_path(__FILE__) }
  end
end
