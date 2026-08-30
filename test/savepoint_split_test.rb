# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/bridge"

# Intent 303: the intent-dir savepoint ledger and the stage derivation moved out of
# bridge.rb into scripts/lib/savepoint.rb. This file proves the split: the ledger
# loads without the bridge, every moved name answers on Savepoint and not on Bridge,
# no caller still reaches a moved name through Bridge, and the eight files whose only
# bridge use was a moved name no longer require the bridge at all.
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

  # Pointer-side names that stay on Bridge (spec D2; intent_id_from_dir per review B1).
  # The seven helpers left on Bridge after the bridge JSON itself went (intent 307).
  STAYING_METHODS = %i[
    intent_id_from_dir deep_merge read_project_config intent_active? index_entry_match blank? skill_ref
  ].freeze

  # Bridge names the moved code must never call bare (they stayed behind).
  STAYING_NAMES = %w[blank? index_entry_match skill_ref intent_active?].freeze

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
      assert_empty leaked, "savepoint.rb pulled in the bridge's dependencies: #{leaked.inspect}"
    end
  end

  def test_moved_methods_respond_on_savepoint_and_not_on_bridge
    missing = MOVED_METHODS.reject { |m| Savepoint.respond_to?(m) }
    assert_empty missing, "Savepoint lacks #{missing.inspect}"
    left = MOVED_METHODS.select { |m| Bridge.respond_to?(m) }
    assert_empty left, "Bridge still answers #{left.inspect} (a shim or a forgotten delete)"
  end

  def test_pointer_names_stay_on_bridge_and_not_on_savepoint
    missing = STAYING_METHODS.reject { |m| Bridge.respond_to?(m) }
    assert_empty missing, "Bridge lost #{missing.inspect}"
    strayed = STAYING_METHODS.select { |m| Savepoint.respond_to?(m) }
    assert_empty strayed, "Savepoint answers pointer-side #{strayed.inspect}"
    assert_equal "96", Bridge.intent_id_from_dir("/s/store/96--demo")
  end

  def test_moved_constants_live_on_savepoint_only_and_stages_is_gone
    MOVED_CONSTS.each do |c|
      assert Savepoint.const_defined?(c, false), "Savepoint::#{c} missing"
      refute Bridge.const_defined?(c, false), "Bridge::#{c} must not be re-exported"
    end
    assert_equal "<!-- plastic:placeholder -->", Savepoint::PLACEHOLDER_SENTINEL
    assert_equal "savepoint.md", Savepoint::SAVEPOINT_FILE
    refute Bridge.const_defined?(:STAGES, false), "dead STAGES rides along on Bridge"
    refute Savepoint.const_defined?(:STAGES, false), "dead STAGES was moved instead of deleted"
  end

  def test_savepoint_never_names_the_bridge_and_bridge_requires_savepoint
    sp = File.read(File.join(REPO, "scripts", "lib", "savepoint.rb"))
    refute_match(/\bBridge\b/, sp, "savepoint.rb must not reference Bridge")
    refute_match(/require_relative\s+["'](bridge|lock|worktree)["']/, sp)
    br = File.read(File.join(REPO, "scripts", "lib", "bridge.rb"))
    refute_match(/require_relative\s+["']savepoint["']/, br, "bridge.rb needs no savepoint since the bridge JSON went (intent 307)")
    refute_match(/^require\s+["'](socket|tempfile)["']/, br, "bridge.rb keeps a dead require")
  end

  def test_savepoint_source_calls_no_staying_bridge_name
    sp = File.read(File.join(REPO, "scripts", "lib", "savepoint.rb"))
    offenders = STAYING_NAMES.select { |n| sp.match?(/(?<![.\w])#{Regexp.escape(n)}(?![\w?!])/) }
    assert_empty offenders, "savepoint.rb calls a name that stayed on Bridge: #{offenders.inspect}"
  end

  def test_bridge_internal_uses_of_moved_names_are_qualified
    offenders = []
    File.foreach(File.join(REPO, "scripts", "lib", "bridge.rb")).with_index(1) do |line, n|
      code = line.chomp.sub(/#.*/, "")
      MOVED_METHODS.each do |m|
        name = Regexp.escape(m.to_s)
        offenders << "#{n}: #{m}" if code.match?(/(?<![.\w:])#{name}(?![\w?!])/)
      end
      MOVED_CONSTS.each do |c|
        offenders << "#{n}: #{c}" if code.match?(/(?<![.\w:])#{c}(?![\w])/)
      end
    end
    assert_empty offenders, "bridge.rb uses a moved name without Savepoint.: #{offenders.first(20).inspect}"
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
    assert_empty offenders, "skill recipes still load the bridge for a moved method:\n#{offenders.join("\n")}"
  end

  def test_bridge_free_files_require_savepoint_not_bridge
    BRIDGE_FREE.each do |rel|
      src = File.read(File.join(REPO, rel))
      refute_match(/\bBridge\b/, src, "#{rel} still names Bridge")
      refute_match(/require_relative\s+["'][^"']*bridge["']/, src, "#{rel} still requires bridge")
      assert_match(/require_relative\s+["'][^"']*savepoint["']/, src, "#{rel} must require savepoint")
    end
  end

  def test_plastic_lock_stays_pointer_side_and_requires_no_savepoint
    src = File.read(File.join(REPO, "scripts", "plastic-lock"))
    refute_match(/require_relative\s+["'][^"']*savepoint["']/, src)
    assert_match(/Bridge\.intent_id_from_dir/, src)
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

  def test_bridge_shrank_and_the_manifest_ships_savepoint
    assert_operator File.foreach(File.join(REPO, "scripts", "lib", "bridge.rb")).count, :<, 800
    manifest = File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))
    assert_includes manifest, '"scripts/lib/savepoint.rb" => "scripts/lib/savepoint.rb"'
  end

  private

  def scan_files
    SCAN_ROOTS.flat_map { |root| p = File.join(REPO, root); File.file?(p) ? [p] : Dir[File.join(p, "**", "*")].select { |f| File.file?(f) } }
             .reject { |f| f == File.expand_path(__FILE__) || f.end_with?("scripts/lib/savepoint.rb") }
  end
end
