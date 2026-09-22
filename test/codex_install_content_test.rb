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
  #
  # The two plastic-doctor/report.md entries (Spec D5, sample doctor output) were
  # dropped by intent 372 (family 4): the doctor skill, including report.md, is gone,
  # replaced by the `plastic doctor` command, whose own output is not installed under
  # skills/ and so is outside this test's installed_md scan.
  ALLOWED = [].freeze

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

  # The intent-creating/lifecycle.md half of this pin was retired by intent 372 (family 2):
  # intent-creating moved into `plastic intent new`, a command; its files are gone.
  #
  # The remaining plastic-auto/SKILL.md half (test_the_breaking_line_resolves_on_codex) was
  # retired by intent 372 (family 5): skills/auto/SKILL.md, the sole shipped file that carried
  # the literal `~/.plastic/templates/outcome.md` breaking line, is gone with no successor
  # file carrying that exact path, so there is no fixture left for this regression check to
  # read.

  # test_claude_roots_are_rewritten was retired by intent 372 (family 3): it read
  # the installed plastic-dashboard/SKILL.md for a ~/.claude/skills/ path this
  # rewrite turns into ~/.agents/skills/. That skill is gone (its board and
  # ranking rules moved into `plastic status`), and no other file the kept
  # skills install still carries a real ~/.claude root to rewrite. The mechanism
  # itself stays covered at the unit level by harness_text_test.rb's
  # test_rule_order_pinned, which needs no real dashboard data from the shipped
  # tree.

  # test_near_miss_paths_survive_untouched was retired by intent 372 (family 4): it
  # read the installed plastic-auto/SKILL.md for the relative path
  # "../plastic-conventions/references/", which named the conventions skill's chapter
  # directory. That skill and its references/ directory are gone (chapters moved to
  # docs/help/*.md, read through `plastic help TOPIC`), and no other file the kept
  # skills install still carries a real near-miss path shaped like a slash-prefixed
  # skill invocation. The mechanism itself (the slash-prefix regex's lookbehind
  # leaving a relative path alone) stays covered at the unit level by
  # harness_text_test.rb's test_relative_path_left_alone, which needs no real
  # near-miss data from the shipped tree.

  def test_shared_fragments_are_never_transformed
    %w[_decision-tables.md].each do |name|
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
