# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/arm"
require_relative "../scripts/lib/lock"
require_relative "../scripts/lib/index_entry"
require_relative "../scripts/lib/project_config"

# Intent 303 moved the intent-dir savepoint ledger and the stage derivation out of
# bridge.rb into scripts/lib/savepoint.rb. Intent 344 retired bridge.rb itself: its
# remaining pointer-side helpers now answer on Arm, Lock, IndexEntry, and ProjectConfig.
# This file proves both splits still hold: the ledger loads standalone, every moved
# name answers on Savepoint, the retired helpers answer on their new owners, and no
# caller still reaches a moved name through the retired module.
class SavepointSplitTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  MOVED_METHODS = %i[
    intent_file intent_dir_for stage_file_present? has_real_action?
    derive_stage has_files missing_for_stage savepoint_milestone savepoint_recorded_milestones
    savepoint_recorded_pairs append_savepoint_line append_savepoint savepoint_started_milestone
    append_started_savepoint append_exec_started append_terminal_savepoint
    rebuild_savepoint savepoint_file_landing_pairs savepoint_phantom_lines
  ].freeze

  MOVED_CONSTS = %i[PLACEHOLDER_SENTINEL SAVEPOINT_FILE TERMINAL_DISPOSITIONS SAVEPOINT_STATE_PREREQUISITES].freeze

  # Files whose only bridge use was a moved name: they require savepoint, not bridge.
  BRIDGE_FREE = %w[
    scripts/lib/insights.rb scripts/lib/outcome_guard.rb scripts/new-intent scripts/agent-report
    scripts/spawn-preamble scripts/hook-record scripts/doctor.rb scripts/maintenance-run
  ].freeze

  SCAN_ROOTS = %w[scripts hooks test docs/architecture.md docs/internals.md].freeze

  MOVED_RE = Regexp.new('Bridge(\.|::)(' + (MOVED_METHODS + MOVED_CONSTS).map { |n| Regexp.escape(n.to_s) }.join("|") + ')(?![A-Za-z0-9_?!])').freeze

  def test_savepoint_loads_standalone_with_no_other_project_file
    Dir.mktmpdir("savepoint-split") do |tmp|
      env = { "RUBYOPT" => nil, "PLASTIC_TMP" => tmp, "CLAUDE_CODE_SESSION_ID" => nil }
      lib = File.join(REPO, "scripts", "lib", "savepoint.rb")
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-e", "require #{lib.inspect}; puts $LOADED_FEATURES")
      assert status.success?, "savepoint.rb does not load: #{err}"
      loaded = out.lines.map(&:strip)
      project = loaded.select { |f| f.start_with?("#{REPO}/") }.map { |f| f.sub("#{REPO}/", "") }.sort
      assert_equal %w[scripts/lib/savepoint.rb], project
      leaked = loaded.grep(%r{/(bridge|lock|worktree)\.rb\z|/yaml(\.rb)?\z|/socket\.rb\z|/digest\.rb\z})
      assert_empty leaked, "savepoint.rb pulled in unwanted dependencies: #{leaked.inspect}"
    end
  end

  def test_moved_methods_respond_on_savepoint_and_not_on_bridge
    missing = MOVED_METHODS.reject { |m| Savepoint.respond_to?(m) }
    assert_empty missing, "Savepoint lacks #{missing.inspect}"
    refute Object.const_defined?(:Bridge), "Bridge must be fully retired (intent 344)"
  end

  def test_retired_bridge_helpers_answer_on_their_owners
    assert_equal "96", Arm.intent_id_for("/s/store/96--demo")
    merged = ProjectConfig.deep_merge({ "a" => 1, "n" => { "x" => 1 } }, { "n" => { "y" => 2 } })
    assert_equal({ "a" => 1, "n" => { "x" => 1, "y" => 2 } }, merged)
    assert_equal ["AGENTS.md"], ProjectConfig::DEFAULTS["governing_docs"]
    assert IndexEntry.match("- [96 #{IndexEntry::EM_DASH} demo](store/96--demo/96--demo.md)")
    assert IndexEntry.active?("5", store: "irrelevant", index_active_ids: %w[5 6])
    refute IndexEntry.active?("7", store: "irrelevant", index_active_ids: %w[5 6])
    assert_equal "/plastic-doctor", Lock.skill_ref("plastic-doctor")
    refute Object.const_defined?(:Bridge), "Bridge must be fully retired (intent 344)"
  end

  def test_moved_constants_live_on_savepoint_only_and_stages_is_gone
    MOVED_CONSTS.each do |c|
      assert Savepoint.const_defined?(c, false), "Savepoint::#{c} missing"
    end
    assert_equal "<!-- plastic:placeholder -->", Savepoint::PLACEHOLDER_SENTINEL
    assert_equal "savepoint.md", Savepoint::SAVEPOINT_FILE
    refute Savepoint.const_defined?(:STAGES, false), "dead STAGES was moved instead of deleted"
  end

  def test_savepoint_never_names_the_bridge
    sp = File.read(File.join(REPO, "scripts", "lib", "savepoint.rb"))
    refute_match(/\bBridge\b/, sp, "savepoint.rb must not reference Bridge")
    refute_match(/require_relative\s+["'](bridge|lock|worktree)["']/, sp)
  end

  def test_bridge_library_file_is_gone
    refute File.exist?(File.join(REPO, "scripts", "lib", "bridge.rb"))
  end

  def test_no_caller_reaches_a_moved_name_through_bridge_in_code_or_docs
    offenders = []
    scan_files.each do |path|
      File.foreach(path).with_index(1) do |line, n|
        code = line.chomp.sub(/#.*/, "")
        offenders << "#{path.sub("#{REPO}/", "")}:#{n}" if code.match?(MOVED_RE)
      end
    end
    assert_empty offenders, "callers still reach a moved name through Bridge:\n#{offenders.first(40).join("\n")}"
  end

  # The four skill recipes that rebuild the ledger are a live path, not doctrine
  # (review A6, B2): a `-r .../lib/bridge` line that names a moved method breaks.
  def test_no_skill_recipe_loads_the_bridge_to_reach_a_moved_method
    offenders = []
    Dir[File.join(REPO, "skills", "**", "*.md")].each do |path|
      File.foreach(path).with_index(1) do |line, n|
        next unless line.include?("lib/bridge")
        offenders << "#{path.sub("#{REPO}/", "")}:#{n}" if MOVED_METHODS.any? { |m| line.include?(m.to_s) }
      end
    end
    assert_empty offenders, "skill recipes still load the retired bridge for a moved method:\n#{offenders.join("\n")}"
  end

  def test_bridge_free_files_require_savepoint_not_bridge
    BRIDGE_FREE.each do |rel|
      src = File.read(File.join(REPO, rel))
      refute_match(/\bBridge\b/, src, "#{rel} still names Bridge")
      refute_match(/require_relative\s+["'][^"']*bridge["']/, src, "#{rel} still requires bridge")
      assert_match(/require_relative\s+["'][^"']*savepoint["']/, src, "#{rel} must require savepoint")
    end
  end

  def test_plastic_lock_stays_pointer_side_and_names_arm_not_bridge
    src = File.read(File.join(REPO, "scripts", "plastic-lock"))
    refute_match(/require_relative\s+["'][^"']*savepoint["']/, src)
    refute_match(/\bBridge\b/, src)
    assert_match(/Arm\.intent_id_for/, src)
  end

  def test_every_file_using_savepoint_requires_it_itself
    offenders = []
    scan_files.each do |path|
      next unless path.end_with?(".rb") || File.read(path, 2) == "#!"
      src = File.read(path).lines.map { |l| l.chomp.sub(/#.*/, "") }.join("\n")
      next unless src.match?(/\bSavepoint(\.|::)/)
      next if src.match?(/require_relative\s+["'][^"']*savepoint["']/)
      offenders << path.sub("#{REPO}/", "")
    end
    assert_empty offenders, "uses Savepoint without requiring it: #{offenders.inspect}"
  end

  def test_manifest_ships_savepoint_and_not_bridge
    manifest = File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))
    assert_includes manifest, '"scripts/lib/savepoint.rb" => "scripts/lib/savepoint.rb"'
    refute_includes manifest, '"scripts/lib/bridge.rb"'
  end

  private

  def scan_files
    # Intent 342 (G9): test/fixtures/legacy_intents/ and test/fixtures/dogfood_intent/
    # are frozen copies of historical intent records, not shipped tree; the scanner
    # polices what ships, not history quoted verbatim in a fixture (spec.md D15).
    SCAN_ROOTS.flat_map { |root| p = File.join(REPO, root); File.file?(p) ? [p] : Dir[File.join(p, "**", "*")].select { |f| File.file?(f) } }
             .reject { |f| f == File.expand_path(__FILE__) || f.end_with?("scripts/lib/savepoint.rb") }
             .reject { |f| f.start_with?(File.join(REPO, "test/fixtures/legacy_intents/")) || f.start_with?(File.join(REPO, "test/fixtures/dogfood_intent/")) }
  end
end
