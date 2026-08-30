# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/savepoint"
require_relative "../scripts/lib/agent_models"
require_relative "../scripts/lib/skill_lint"

# Intent 304: the intent tier, the spec header, the start ceremony, six stage agents, and
# seventeen skill directories are gone from the tree. This file is the reverse-dependency
# acceptance test, the shape of gates_removed_test: removed files absent, the exact skill
# and agent sets, no tier grammar, no dead chapter load line, a removed-name scan with the
# `removed in 2.0` note convention, the legacy-ledger compatibility rule, and skill-lint clean.
class Subtraction304Test < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  REMOVED_FILES = %w[
    scripts/lib/spec_header.rb scripts/lib/start_intent.rb scripts/start-intent
    test/spec_header_test.rb test/start_intent_test.rb
    agents/plastic-intent-discovery.md agents/plastic-brainstorming.md
    agents/plastic-spec-specialist.md agents/plastic-planner.md
    agents/plastic-intent-curator.md agents/plastic-future-intent-researcher.md
    skills/_active-intent-gate.md skills/doctor/references/gates-stuck-detection.md
    skills/auto/references/tiers.md
    skills/conventions/references/gates-and-enforcement.md
    skills/conventions/references/tiers-and-dispatch.md
  ].freeze

  REMOVED_SKILL_DIRS = %w[
    intent-discovering intent-planning intent-linking intent-savepoint store-curating
    store-indexing skill-creating skill-evaluating intent-brainstorming intent-grilling
    intent-researching continuing project-continuing roadmap-continuing intent-starting
    intent-locking store-provisioning
  ].freeze

  KEPT_SKILL_DIRS = %w[
    agent-advisor auto conventions dashboard direct doctor feedback install intent-continuing
    intent-creating intent-ending intent-executing intent-speccing project-creating releasing
    roadmap rollback tutorial uninstall update
  ].freeze

  KEPT_AGENTS = %w[plastic-advisor.md plastic-enforcer.md plastic-executor.md plastic-faux-advisor.md].freeze

  MOVED_DOCS = %w[
    docs/skill-authoring/creating/SKILL.md docs/skill-authoring/creating/scripts/scaffold.rb
    docs/skill-authoring/evaluating/SKILL.md
  ].freeze

  # Names that may appear nowhere in the scanned roots except on a line that carries the
  # 2.0 removal note (the 302 convention). Merged skills are not listed: their names are
  # re-pointed to the new home, so a survivor is a plain bug the scan should catch too.
  REMOVED_NAMES = %w[
    plastic-intent-discovering plastic-intent-planning plastic-intent-linking
    plastic-intent-savepoint plastic-store-curating plastic-store-indexing
    plastic-skill-creating plastic-skill-evaluating plastic-intent-brainstorming
    plastic-intent-grilling plastic-intent-researching plastic-continuing
    plastic-project-continuing plastic-roadmap-continuing plastic-intent-starting
    plastic-intent-locking plastic-store-provisioning
    plastic-planner plastic-brainstorming plastic-spec-specialist plastic-intent-discovery
    plastic-intent-curator plastic-future-intent-researcher
    gates-and-enforcement.md tiers-and-dispatch.md gates-stuck-detection.md
    _active-intent-gate.md spec_header.rb SpecHeader start_intent.rb start-intent
    savepoint_tier
  ].freeze

  SCAN_ROOTS = %w[scripts hooks test skills agents templates PLASTIC.md README.md docs/architecture.md
                  docs/internals.md docs/guides/reading-the-ledgers.md].freeze
  REMOVAL_NOTE = /removed in 2\.0|retired in 2\.0|left with the gates/.freeze

  # Other senses of the word "tier" that the cut must leave alone (plan review A2): the store
  # tier, the harness support tier, doctor's core run tier, the knowledge-graph link tiers.
  KEPT_TIER_SENSES = {
    "scripts/lib/roadmap_savepoint.rb" => "the tier's INDEX",
    "scripts/agent-report" => "Tier B/C",
    "scripts/update.rb" => "fast core tier",
    "scripts/link-suggest" => "Tiers, by context influence",
    "skills/roadmap/SKILL.md" => "global tier",
  }.freeze

  def test_removed_files_are_gone_and_moved_docs_are_present
    present = REMOVED_FILES.select { |rel| File.exist?(File.join(REPO, rel)) }
    assert_empty present, "still on disk: #{present.inspect}"
    dirs = REMOVED_SKILL_DIRS.select { |d| File.directory?(File.join(REPO, "skills", d)) }
    assert_empty dirs, "skill directories still on disk: #{dirs.inspect}"
    missing = MOVED_DOCS.reject { |rel| File.exist?(File.join(REPO, rel)) }
    assert_empty missing, "moved authoring docs missing: #{missing.inspect}"
  end

  def test_skill_tree_is_exactly_the_twenty_plus_decision_tables
    entries = Dir.children(File.join(REPO, "skills")).sort
    assert_equal (KEPT_SKILL_DIRS + ["_decision-tables.md"]).sort, entries
    KEPT_SKILL_DIRS.each do |d|
      assert File.file?(File.join(REPO, "skills", d, "SKILL.md")), "#{d} has no SKILL.md"
    end
  end

  def test_agents_are_exactly_four_and_tier_defaults_match
    assert_equal KEPT_AGENTS, Dir.children(File.join(REPO, "agents")).sort
    assert_equal %w[plastic-enforcer plastic-executor], AgentModels::TIER_DEFAULTS.keys.sort
  end

  def test_no_intent_tier_grammar_anywhere_in_the_shipped_tree
    offenders = []
    scan_files(%w[scripts hooks test skills agents templates PLASTIC.md]).each do |path|
      File.foreach(path).with_index(1) do |line, n|
        next unless line.match?(/^Tier: |Tier: S|S\|M\|L|per-tier|Settled: yes|\bSpecHeader\b|savepoint_tier|TIER: S/)
        next if line.match?(REMOVAL_NOTE)
        offenders << "#{path.sub("#{REPO}/", "")}:#{n}"
      end
    end
    assert_empty offenders, "tier grammar survives:\n#{offenders.first(30).join("\n")}"
    refute Savepoint.respond_to?(:savepoint_tier)
  end

  def test_the_other_senses_of_tier_are_left_alone
    KEPT_TIER_SENSES.each do |rel, phrase|
      assert_includes File.read(File.join(REPO, rel)), phrase, "#{rel} lost a non-intent tier phrase"
    end
  end

  # skill-lint reports a references/ file nobody mentions, never a mention of a file that is gone
  # (plan review A5): every `references/<name>.md` named under skills must exist beside its skill.
  def test_every_referenced_skill_reference_file_exists
    offenders = []
    Dir[File.join(REPO, "skills", "*", "**", "*.md")].each do |path|
      skill_dir = path.sub(%r{(#{Regexp.escape(File.join(REPO, "skills"))}/[^/]+)/.*}, '\1')
      File.foreach(path).with_index(1) do |line, n|
        line.scan(%r{(?<![\w/.-])references/([a-z0-9-]+\.md)}).flatten.each do |name|
          next if File.file?(File.join(skill_dir, "references", name))
          # a skill may cite another skill's reference by name ("`plastic-roadmap`'s `references/file-format.md`")
          next unless Dir[File.join(REPO, "skills", "*", "references", name)].empty?
          offenders << "#{path.sub("#{REPO}/", "")}:#{n}: references/#{name}"
        end
      end
    end
    assert_empty offenders, "dead references/ pointers:\n#{offenders.join("\n")}"
  end

  def test_no_load_line_names_a_deleted_chapter
    offenders = []
    scan_files(%w[skills agents PLASTIC.md docs/architecture.md docs/internals.md]).each do |path|
      File.foreach(path).with_index(1) do |line, n|
        next unless line.match?(/gates-and-enforcement|tiers-and-dispatch|tiers\.md|gates-stuck-detection/)
        next if line.match?(REMOVAL_NOTE)
        offenders << "#{path.sub("#{REPO}/", "")}:#{n}"
      end
    end
    assert_empty offenders, "dead chapter load lines:\n#{offenders.join("\n")}"
  end

  def test_removed_names_appear_only_on_removal_note_lines
    re = Regexp.new(REMOVED_NAMES.map { |n| Regexp.escape(n) }.join("|"))
    offenders = []
    scan_files(SCAN_ROOTS).each do |path|
      File.foreach(path).with_index(1) do |line, n|
        next unless line.match?(re)
        next if line.match?(REMOVAL_NOTE)
        offenders << "#{path.sub("#{REPO}/", "")}:#{n}: #{line.strip[0, 80]}"
      end
    end
    assert_empty offenders, "removed names outside a removal note:\n#{offenders.first(40).join("\n")}"
  end

  def test_savepoint_loads_with_no_other_project_file
    Dir.mktmpdir("subtraction-304") do |tmp|
      env = { "RUBYOPT" => nil, "PLASTIC_TMP" => tmp, "CLAUDE_CODE_SESSION_ID" => nil }
      lib = File.join(REPO, "scripts", "lib", "savepoint.rb")
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-e", "require #{lib.inspect}; puts $LOADED_FEATURES")
      assert status.success?, err
      project = out.lines.map(&:strip).select { |f| f.start_with?("#{REPO}/") }.map { |f| f.sub("#{REPO}/", "") }
      assert_equal %w[scripts/lib/savepoint.rb], project
    end
  end

  # A Plastic 1.x ledger carries a `Tier  M` line right after the spec.md milestone. The alpha
  # must read that store untouched: the line is not a phantom, and a rebuild simply drops it.
  def test_legacy_tier_ledger_line_is_inert_and_dropped_on_rebuild
    Dir.mktmpdir("subtraction-304-store") do |tmp|
      dir = File.join(tmp, "store", "42--legacy")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "42--legacy.md"), "# Legacy\n")
      File.write(File.join(dir, "spec.md"), "Tier: M\n\n# Spec: legacy\n")
      File.write(File.join(dir, "savepoint.md"),
                 "2026-01-01T00:00:00Z  What  42--legacy.md\n" \
                 "2026-01-01T00:00:01Z  Why  spec.md created\n" \
                 "2026-01-01T00:00:01Z  Tier  M\n")
      assert_equal [], Savepoint.savepoint_phantom_lines(dir)
      count = Savepoint.rebuild_savepoint(dir)
      lines = File.read(File.join(dir, "savepoint.md")).lines
      assert_equal count, lines.length
      assert_equal 2, lines.length
      refute lines.any? { |l| l.include?("  Tier  ") }
      assert_equal [], Savepoint.savepoint_phantom_lines(dir)
    end
  end

  def test_intent_continuing_asks_no_mode_and_routes_three_ways
    body = File.read(File.join(REPO, "skills", "intent-continuing", "SKILL.md"))
    refute_match(/auto or guided\?/i, body)
    %w[Project route Intent route Roadmap route].each { |h| assert_includes body, h }
    %w[board-fill.md boarding-matrix.md liveness-ranking.md context-management.md].each do |ref|
      assert File.file?(File.join(REPO, "skills", "intent-continuing", "references", ref)), "#{ref} missing"
    end
  end

  def test_intent_speccing_carries_grill_and_research_modes
    body = File.read(File.join(REPO, "skills", "intent-speccing", "SKILL.md"))
    %w[Grill\ mode Research\ mode insight-append design-principles.md].each { |s| assert_includes body, s }
  end

  def test_doctor_skill_carries_locks_and_provisioning
    body = File.read(File.join(REPO, "skills", "doctor", "SKILL.md"))
    assert_includes body, "plastic-lock"
    assert_includes body, "provision-project-store"
    assert_includes body, "reclaim"
  end

  def test_advisor_brief_keys_on_effort_not_a_tier_letter
    %w[agents/plastic-advisor.md agents/plastic-faux-advisor.md skills/agent-advisor/SKILL.md
       skills/agent-advisor/references/advisor-protocol.md].each do |rel|
      body = File.read(File.join(REPO, rel))
      refute_match(/TIER: |S, M, or L|\bL tier\b|\bS tier\b/, body, "#{rel} still carries the S/M/L brief grammar")
      assert_includes body, "EFFORT", "#{rel} lost the effort line"
    end
  end

  def test_skill_lint_is_clean
    result = SkillLint.new(skills_dir: File.join(REPO, "skills")).run
    assert_empty result.violations, result.violations.map { |v| "#{v[:skill]}: #{v[:message]}" }.join("\n")
  end

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
    Dir.mktmpdir("subtraction-304-tmp") do |tmp|
      env = { "RUBYOPT" => nil, "PLASTIC_TMP" => tmp, "CLAUDE_CODE_SESSION_ID" => nil }
      scripts = Dir[File.join(REPO, "scripts", "*")].select { |f| File.file?(f) }
      ruby_scripts = scripts.select { |f| File.open(f, &:readline).to_s.include?("ruby") rescue false }
      ruby_scripts.each do |f|
        _out, err, status = Open3.capture3(env, RbConfig.ruby, "-c", f)
        assert status.success?, "#{f} does not parse: #{err}"
      end
      Dir[File.join(REPO, "scripts", "lib", "*.rb")].each do |f|
        _out, err, status = Open3.capture3(env, RbConfig.ruby, "-e", "require #{f.inspect}")
        assert status.success?, "#{f} does not load: #{err}"
      end
    end
  end

  private

  def scan_files(roots)
    roots.flat_map do |root|
      p = File.join(REPO, root)
      File.file?(p) ? [p] : Dir[File.join(p, "**", "*")].select { |f| File.file?(f) }
    end.reject { |f| f == File.expand_path(__FILE__) }
  end
end
