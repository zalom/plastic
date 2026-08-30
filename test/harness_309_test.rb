# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/hook_registry"

# Intent 309 contract pins: the power-tools hook is retired on both harnesses (files gone,
# manifest rows gone, name in RETIRED_HOOK_NAMES, UserPromptSubmit carries capture only),
# and the docs say what the research proved (Codex ships Stop and SessionEnd; the close
# hook runs on Codex through the detached hand-off). Literal names below carry a removal
# note on their line so test/gates_removed_test.rb's own scan reads them as notes.
class Harness309Test < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  REMOVAL_NOTE = /removed in 2\.0|retired in 2\.0/.freeze

  DELETED = [
    "hooks/power-tools", # removed in 2.0 (intent 309)
    "scripts/hook-power-tools", # removed in 2.0 (intent 309)
    "scripts/lib/qmd_hook.rb", # removed in 2.0 (intent 309)
    "test/qmd_hook_test.rb", # removed in 2.0 (intent 309)
  ].freeze

  DOC_ROOTS = %w[AGENTS.md README.md PLASTIC.md docs skills].freeze
  STALE_PHRASES = [
    "hook-power-tools", # removed in 2.0 (intent 309)
    "hooks/power-tools", # removed in 2.0 (intent 309)
    "power-tools hook", # removed in 2.0 (intent 309)
    "not in the Codex projection", # retired in 2.0 (intent 309)
    "until intent 309", # retired in 2.0 (intent 309)
    "recommends the power tools", # retired in 2.0 (intent 309)
    "Intent 309 regenerates", # retired in 2.0 (intent 309)
    "Claude Code only until", # retired in 2.0 (intent 309)
    "does not yet relay", # retired in 2.0 (intent 309)
  ].freeze

  def files_under(root)
    path = File.join(REPO, root)
    return [path] if File.file?(path)

    Dir.glob(File.join(path, "**", "*")).select { |f| File.file?(f) && f !~ %r{/(node_modules|\.git|reviews)/} }
  end

  def test_the_power_tools_files_are_gone
    present = DELETED.select { |rel| File.exist?(File.join(REPO, rel)) }
    assert_empty present, "still present: #{present.inspect}"
  end

  def test_the_manifest_lists_no_power_tools_script_and_still_ships_power_tools_lib
    manifest = File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))
    refute_match(/hook-power-tools/, manifest)
    refute_match(/qmd_hook\.rb/, manifest)
    assert_match(%r{"scripts/lib/power_tools\.rb"}, manifest, "doctor's Serena and Enola checks still use it")
  end

  def test_power_tools_is_retired_and_user_prompt_submit_carries_capture_only
    assert_includes HookRegistry::RETIRED_HOOK_NAMES, "power-tools"
    refute_includes HookRegistry.claude_launcher_names, "plastic-power-tools"
    refute_includes HookRegistry.codex_hook_names, "power-tools"
    names = HookRegistry.events["UserPromptSubmit"].flat_map { |g| g["hooks"].map { |h| h["name"] } }
    assert_equal ["capture"], names
  end

  def test_the_five_event_map_is_the_same_on_both_harnesses
    claude = HookRegistry.events.keys.sort
    codex = HookRegistry.codex_hooks_json(dispatcher_path: "/x/codex-hook").keys.sort
    assert_equal %w[PostToolUse PreCompact SessionEnd SessionStart UserPromptSubmit], claude
    assert_equal claude, codex
    refute_includes claude, "Stop"
  end

  def test_no_doc_still_describes_the_hook_or_says_codex_lacks_session_end
    hits = []
    DOC_ROOTS.flat_map { |r| files_under(r) }.each do |file|
      File.foreach(file).with_index(1) do |line, no|
        next if line.match?(REMOVAL_NOTE)

        phrase = STALE_PHRASES.find { |p| line.include?(p) }
        hits << "#{file.sub("#{REPO}/", "")}:#{no}: #{phrase}" if phrase
      end
    rescue ArgumentError
      next
    end
    assert_empty hits, "stale doc lines:\n#{hits.join("\n")}"
  end

  def test_harness_adapters_states_the_codex_correction
    doc = File.read(File.join(REPO, "docs", "reference", "harness-adapters.md"))
    assert_match(/ships both `Stop`\s+and `SessionEnd`/, doc)
    assert_match(/rust-v0\.149\.1/, doc)
    assert_match(/3.second/, doc)
  end
end
