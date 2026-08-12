# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "digest"
require_relative "../scripts/lib/installer_core"

# Intent 239: the installed Codex skill tree must not speak Claude Code.
#
# This test installs into throwaway tmpdirs and scans the INSTALLED tree, never the
# repo tree. That distinction is the whole point (intent 261): a repo-tree scan cannot
# see what the installer's copy path actually produced.
class CodexInstallContentTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  SKILLS_SRC = File.join(REPO, "skills")

  def setup
    @home = Dir.mktmpdir("239-plastic-home")   # plastic_home
    @agent_dir = Dir.mktmpdir("239-agents")    # ~/.agents equivalent
    @codex_home = Dir.mktmpdir("239-codex")    # ~/.codex equivalent
    @core = InstallerCore.new(package_root: REPO, plastic_home: @home, version: "1.0.0-test")
    @core.install_codex({ name: "Codex CLI", dir: @agent_dir, home_dir: @codex_home }, false)
    @skills_root = File.join(@agent_dir, "skills")
  end

  def teardown
    [@home, @agent_dir, @codex_home].each { |d| FileUtils.rm_rf(d) }
  end

  def installed_md
    Dir.glob(File.join(@skills_root, "**", "*.md")).select { |p| File.file?(p) }
  end

  def rel(path)
    path.sub("#{@skills_root}/", "")
  end

  def skill_names
    Dir.children(SKILLS_SRC).select { |e| File.directory?(File.join(SKILLS_SRC, e)) }
  end

  # "claude home path" stops at a backtick as well as whitespace: the corpus wraps
  # paths in markdown code spans (`` `~/.claude/hooks/plastic-*` ``), and the closing
  # backtick is not part of the path. Without this the match would swallow it, and
  # the exact-text allowlist comparison below would never line up with the entry's
  # clean path text.
  def patterns
    alt = skill_names.sort_by { |n| -n.length }.map { |n| Regexp.escape(n) }.join("|")
    {
      "CLAUDE_PLUGIN_ROOT" => /\$\{CLAUDE_PLUGIN_ROOT\}/,
      "claude home path" => %r{~/\.claude/[^\s`]*},
      "claude slash prefix" => %r{(?<![\w./~*-])/plastic-(?:#{alt})(?![\w-])},
    }
  end

  # Every entry is (installed relative path, exact matched text, why it is allowed to
  # survive on a Codex install). An entry that stops matching anything is a dead entry
  # and fails test_no_dead_allowlist_entries below.
  ALLOWED = [
    ["plastic-skill-creating/references/hooks.md", "${CLAUDE_PLUGIN_ROOT}",
     "Spec D3. These two lines explain Claude Code's placeholder convention TO SKILL " \
     "AUTHORS. Rewriting the token would turn a true sentence into a false one, and " \
     "nothing on Codex executes them."],
    ["plastic-uninstall/SKILL.md", "~/.claude/hooks/plastic-*",
     "Spec D5. Codex installs no per-agent hook launchers, so there is no Codex path to " \
     "substitute. The correct Codex text is a rewrite of the surrounding sentence, which " \
     "is doc authoring rather than an install-time transform."],
    ["plastic-uninstall/SKILL.md", "~/.claude/hooks",
     "Spec D5. The same sentence's verification command (`ls ~/.claude/hooks | grep`). " \
     "Harmless on Codex (it returns nothing, which is the correct answer there) and it " \
     "has no Codex equivalent to point at."],
    ["plastic-doctor/report.md", "~/.claude/hooks/plastic-session-start",
     "Spec D5. Sample doctor OUTPUT, printed inside the report template as an example " \
     "of the format for a Claude install. Not an instruction to the agent."],
    ["plastic-doctor/report.md", "~/.claude/hooks/plastic-gate-check",
     "Spec D5. Same sample output block."],
  ].freeze

  # Coverage is checked per MATCH, not per line: the allowlist clears only a match
  # whose own matched text is IDENTICAL to an entry's allow_text for that path. A
  # per-line check (line.include?(allow_text)) would let any new Claude-ism sitting
  # on the same physical line as an allowlisted string ride along uncaught, since a
  # line containing the allowlisted substring also "includes" it regardless of what
  # else the line contains.
  def test_no_unallowlisted_claude_isms_in_the_installed_codex_tree
    offenders = []
    installed_md.each do |path|
      content = File.read(path)
      content.each_line.with_index(1) do |line, lineno|
        patterns.each_value do |re|
          line.scan(re).each do |m|
            matched = m.is_a?(String) ? m : Regexp.last_match(0)
            matched = Regexp.last_match(0) if matched.nil?
            covered = ALLOWED.any? do |(allow_path, allow_text, _reason)|
              rel(path) == allow_path && matched == allow_text
            end
            offenders << "#{rel(path)}:#{lineno}: #{matched.inspect}" unless covered
          end
        end
      end
    end
    assert_empty offenders, "unallowlisted Claude-isms survived the Codex install:\n#{offenders.join("\n")}"
  end

  def test_no_dead_allowlist_entries
    dead = ALLOWED.reject do |(allow_path, allow_text, _reason)|
      full = File.join(@skills_root, allow_path)
      File.file?(full) && File.read(full).include?(allow_text)
    end
    assert_empty dead, "allowlist entries that matched nothing in the installed tree:\n#{dead.inspect}"
  end

  def test_the_three_breaking_lines_resolve_on_codex
    creating_skill = File.read(File.join(@skills_root, "plastic-intent-creating", "SKILL.md"))
    lifecycle = File.read(File.join(@skills_root, "plastic-intent-creating", "references", "lifecycle.md"))
    auto_skill = File.read(File.join(@skills_root, "plastic-auto", "SKILL.md"))

    assert_includes creating_skill, "$HOME/.plastic/scripts/new-intent"
    assert_includes lifecycle, "$HOME/.plastic/scripts/new-intent"
    assert_includes auto_skill, "$HOME/.plastic/templates/outcome.md"

    refute_includes creating_skill, "CLAUDE_PLUGIN_ROOT"
    refute_includes lifecycle, "CLAUDE_PLUGIN_ROOT"
    refute_includes auto_skill, "CLAUDE_PLUGIN_ROOT"
  end

  def test_skill_authoring_docs_keep_the_placeholder
    installed = File.join(@skills_root, "plastic-skill-creating", "references", "hooks.md")
    source = File.join(SKILLS_SRC, "skill-creating", "references", "hooks.md")
    assert_equal Digest::SHA256.file(source).hexdigest, Digest::SHA256.file(installed).hexdigest
  end

  def test_claude_roots_are_rewritten
    uninstall_skill = File.read(File.join(@skills_root, "plastic-uninstall", "SKILL.md"))
    doctor_skill = File.read(File.join(@skills_root, "plastic-doctor", "SKILL.md"))
    dashboard_skill = File.read(File.join(@skills_root, "plastic-dashboard", "SKILL.md"))

    assert_includes uninstall_skill, "~/.agents/skills/plastic-*/"
    assert_includes uninstall_skill, "~/.agents/plastic/"
    assert_includes uninstall_skill, "~/.codex/hooks.json"
    assert_includes doctor_skill, "~/.agents/plastic/manifest.json"
    assert_includes dashboard_skill, "~/.agents/skills/plastic-dashboard/templates/"
  end

  def test_near_miss_paths_survive_untouched
    auto_skill = File.read(File.join(@skills_root, "plastic-auto", "SKILL.md"))
    gates_stuck = File.read(File.join(@skills_root, "plastic-doctor", "references", "gates-stuck-detection.md"))

    assert_includes auto_skill, "../plastic-conventions/references/"
    assert_includes gates_stuck, "/tmp/plastic-{session}.json"
  end

  def test_shared_fragments_are_never_transformed
    %w[_active-intent-gate.md _decision-tables.md].each do |name|
      installed = File.join(@home, name)
      source = File.join(SKILLS_SRC, name)
      assert_equal Digest::SHA256.file(source).hexdigest, Digest::SHA256.file(installed).hexdigest,
        "#{name} must be byte-identical between source and the shared plastic_home"
    end
  end

  def test_claude_install_is_byte_identical_to_source
    claude_dir = Dir.mktmpdir("239-claude-agents")
    home = Dir.mktmpdir("239-claude-home")
    core = InstallerCore.new(package_root: REPO, plastic_home: home, version: "1.0.0-test")
    core.install_claude({ name: "Claude Code", dir: claude_dir }, false, argv: ["--no-statusline"])

    mismatches = installed_vs_source_mismatches(File.join(claude_dir, "skills"))
    assert_empty mismatches, "install_claude produced content that differs from source:\n#{mismatches.join("\n")}"
  ensure
    FileUtils.rm_rf(claude_dir)
    FileUtils.rm_rf(home)
  end

  def test_hermes_install_is_byte_identical_to_source
    hermes_dir = Dir.mktmpdir("239-hermes-agents")
    home = Dir.mktmpdir("239-hermes-home")
    core = InstallerCore.new(package_root: REPO, plastic_home: home, version: "1.0.0-test")
    core.install_hermes({ name: "Hermes", dir: hermes_dir }, false)

    mismatches = installed_vs_source_mismatches(File.join(hermes_dir, "skills"))
    assert_empty mismatches, "install_hermes produced content that differs from source:\n#{mismatches.join("\n")}"
  ensure
    FileUtils.rm_rf(hermes_dir)
    FileUtils.rm_rf(home)
  end

  # Maps every installed skills/plastic-<name>/**/*.md back to its skills/<name>/**
  # source and compares SHA256, so a failure message stays readable (no giant diff).
  def installed_vs_source_mismatches(installed_skills_root)
    mismatches = []
    Dir.glob(File.join(installed_skills_root, "**", "*.md")).select { |p| File.file?(p) }.each do |installed|
      rel_path = installed.sub("#{installed_skills_root}/", "")
      segments = rel_path.split(File::SEPARATOR)
      first = segments.shift
      next unless first.start_with?("plastic-")
      source_dir_name = first.sub(/\Aplastic-/, "")
      source = File.join(SKILLS_SRC, source_dir_name, *segments)
      next unless File.file?(source)
      unless Digest::SHA256.file(source).hexdigest == Digest::SHA256.file(installed).hexdigest
        mismatches << "#{rel_path} (source #{source})"
      end
    end
    mismatches
  end
end
