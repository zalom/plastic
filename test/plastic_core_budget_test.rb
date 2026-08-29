# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

# PlasticCoreBudgetTest (intent 223, D7/D12): the regrowth-enforcement
# mechanism. Two prior splits (intents 13b, 127) each shrank PLASTIC.md once
# and it regrew both times because nothing measured it. skill-lint measures
# skill bodies but its scope is hardcoded to skills/*/SKILL.md
# (scripts/doctor.rb:2793) and is advisory in doctor by design (always
# reports "pass"). This test makes the test suite the enforcement mechanism
# instead, because the suite already blocks a commit and a release.
#
# Part A asserts the core budget ceiling (320 lines AND 3000 estimated,
# tightened by intent 304; CoreBudget::Measurement keeps skill-lint's 500 and 5000 so its
# can-fail fixtures still mirror the linter; only the two assertions below carry the tighter bar;
# tokens). Part B asserts the chapter wiring: every
# skills/conventions/references/*.md chapter has a consumer load line, and
# every load line in the skills/ tree resolves to a real chapter file.
#
# Hermetic and DI throughout: CoreBudget.measure and ChapterWiring take a
# string or a path argument, so the exact same code measures the live tree
# and a Dir.mktmpdir fixture. No eval, no ENV variable, no global config
# seam, no network, no reads of ~/.plastic.

# CoreBudget: measures a body's line count and estimated token count using
# the SAME two-line arithmetic as SkillLint#check_body_budget
# (scripts/lib/skill_lint.rb:93-111), so the core-budget check and skill-lint
# never disagree. Not a wrapper around SkillLint: check_body_budget is a
# private method entangled with violation-record construction over a full
# skills_dir tree, not a reusable pure function, so this small DI class ports
# the identical arithmetic rather than reaching into SkillLint's internals
# (scripts/lib/skill_lint.rb and scripts/doctor.rb are left untouched, per
# the action's constraint).
class CoreBudget
  Measurement = Struct.new(:lines, :tokens) do
    def over_line_ceiling?
      lines >= 500
    end

    def over_token_ceiling?
      tokens >= 5000
    end
  end

  def self.measure(body)
    lines = body.lines.count
    tokens = (body.split(/\s+/).reject(&:empty?).length * 1.3).round
    Measurement.new(lines, tokens)
  end
end

# ChapterWiring: derives the chapter set and the consumer wiring from a given
# skills_root (the live repo root, or a Dir.mktmpdir fixture root shaped the
# same way), with no hardcoded skill list where a glob will do.
class ChapterWiring
  LOAD_LINE_RE = %r{\.\./plastic-conventions/references/([a-z0-9-]+\.md)}

  def initialize(skills_root:)
    @skills_root = skills_root
  end

  def chapter_basenames
    Dir.glob(File.join(@skills_root, "skills", "conventions", "references", "*.md"))
       .map { |p| File.basename(p) }.sort
  end

  # Every skills/*/SKILL.md except the router itself (skills/conventions/SKILL.md
  # only ever mentions the pattern with a <chapter> placeholder, never a bound
  # literal load line, so it is not a consumer).
  def consumer_skill_paths
    Dir.glob(File.join(@skills_root, "skills", "*", "SKILL.md")).sort
       .reject { |p| File.basename(File.dirname(p)) == "conventions" }
  end

  # basename => [consuming SKILL.md paths]
  def referenced_basenames
    consumer_skill_paths.each_with_object(Hash.new { |h, k| h[k] = [] }) do |path, acc|
      File.read(path).scan(LOAD_LINE_RE).each { |(basename)| acc[basename] << path }
    end
  end

  def orphaned_chapters
    referenced = referenced_basenames
    chapter_basenames.reject { |name| referenced.key?(name) }
  end

  def unresolved_references
    referenced = referenced_basenames
    existing = chapter_basenames
    referenced.keys.reject { |name| existing.include?(name) }
  end
end

class PlasticCoreBudgetTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)
  PLASTIC_MD = File.join(REPO, "PLASTIC.md")

  def test_plastic_md_exists
    assert File.file?(PLASTIC_MD), "expected #{PLASTIC_MD} to exist"
  end

  def test_live_core_is_under_the_line_ceiling
    measurement = CoreBudget.measure(File.read(PLASTIC_MD))
    assert_operator measurement.lines, :<, 320,
      "PLASTIC.md is #{measurement.lines} lines; must stay under the 320-line ceiling (D7, tightened by 304)"
  end

  def test_live_core_is_under_the_token_ceiling
    measurement = CoreBudget.measure(File.read(PLASTIC_MD))
    assert_operator measurement.tokens, :<, 3000,
      "PLASTIC.md is about #{measurement.tokens} estimated tokens; must stay under the 3000-token ceiling (D7, tightened by 304)"
  end

  # Can-fail proof (intent 208): the budget check must be observed failing on
  # a deliberate over-budget file, on each sub-check independently, so one
  # cannot mask the other. Uses the real boundary (skill-lint treats >= 500
  # and >= 5000 as violations), not a rounded one.
  def test_oversized_fixtures_trip_each_sub_check_independently
    Dir.mktmpdir("plastic-core-budget-test") do |dir|
      over_lines_path = File.join(dir, "over_lines.md")
      # 600 lines, one short word each: lines = 600 (>= 500 ceiling), words =
      # 600 so tokens = 780 (well under the 5000 ceiling). Trips ONLY the
      # line sub-check.
      File.write(over_lines_path, (["x"] * 600).join("\n"))
      over_lines = CoreBudget.measure(File.read(over_lines_path))
      assert over_lines.over_line_ceiling?,
        "fixture #{over_lines_path} has #{over_lines.lines} lines; expected it to trip the >= 500 line ceiling"
      refute over_lines.over_token_ceiling?,
        "fixture #{over_lines_path} unexpectedly tripped the token ceiling too (#{over_lines.tokens} tokens); " \
        "the line sub-check must be provable in isolation"

      over_tokens_path = File.join(dir, "over_tokens.md")
      # 100 lines, 40 words each: lines = 100 (well under the 500 ceiling),
      # words = 4000 so tokens = 5200 (>= 5000 ceiling). Trips ONLY the
      # token sub-check.
      words_per_line = (["word"] * 40).join(" ")
      File.write(over_tokens_path, (["#{words_per_line}"] * 100).join("\n"))
      over_tokens = CoreBudget.measure(File.read(over_tokens_path))
      assert over_tokens.over_token_ceiling?,
        "fixture #{over_tokens_path} has #{over_tokens.tokens} estimated tokens; expected it to trip the >= 5000 token ceiling"
      refute over_tokens.over_line_ceiling?,
        "fixture #{over_tokens_path} unexpectedly tripped the line ceiling too (#{over_tokens.lines} lines); " \
        "the token sub-check must be provable in isolation"
    end
  end
end

class PlasticChapterWiringTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)

  # D5/spec.md's ruled chapter set. A 9th chapter added later without a
  # consumer line is caught by test_every_chapter_has_a_consumer anyway; this
  # test pins the ruled shape itself.
  RULED_CHAPTERS = %w[
    completion-and-done.md
    knowledge-graph.md
    lifecycle-and-savepoints.md
    locks-and-worktrees.md
    maintenance-and-revisions.md
    roadmaps.md
  ].sort.freeze

  def live_wiring
    ChapterWiring.new(skills_root: REPO)
  end

  def test_every_chapter_has_a_consumer
    orphans = live_wiring.orphaned_chapters
    assert_empty orphans,
      "orphaned chapter(s) with no consumer load line: #{orphans.join(', ')}"
  end

  def test_every_load_line_resolves
    dangling = live_wiring.unresolved_references
    assert_empty dangling,
      "load line(s) pointing at a chapter file that does not exist under skills/conventions/references/: " \
      "#{dangling.join(', ')}"
  end

  def test_chapter_set_is_the_ruled_set
    assert_equal RULED_CHAPTERS, live_wiring.chapter_basenames.sort,
      "skills/conventions/references/ chapter set drifted from the ruled 6-chapter set (spec.md; two chapters removed in 2.0, intent 304)"
  end

  # Build a minimal skills tree in a Dir.mktmpdir shaped like the real one
  # (skills/conventions/references/*.md plus skills/*/SKILL.md consumers).
  def build_fixture_tree(dir)
    refs_dir = File.join(dir, "skills", "conventions", "references")
    FileUtils.mkdir_p(refs_dir)
    File.write(File.join(refs_dir, "chapter-a.md"), "# Chapter A\n")
    File.write(File.join(refs_dir, "chapter-b.md"), "# Chapter B\n")

    consumer_dir = File.join(dir, "skills", "consumer")
    FileUtils.mkdir_p(consumer_dir)
    yield File.join(consumer_dir, "SKILL.md")
  end

  # Can-fail proof (intent 208): drop the load line for one chapter and
  # assert the orphan check goes red, naming the orphaned chapter. Hermetic:
  # built and torn down entirely inside a Dir.mktmpdir, never mutates the
  # real skills/ tree.
  def test_orphan_check_can_fail
    Dir.mktmpdir("plastic-chapter-wiring-orphan-test") do |dir|
      build_fixture_tree(dir) do |skill_md|
        # Only chapter-a is loaded; chapter-b's line is deliberately dropped.
        File.write(skill_md, <<~MD)
          ---
          name: plastic-consumer
          description: fixture consumer
          user-invocable: true
          ---

          Read `../plastic-conventions/references/chapter-a.md` for chapter A doctrine.
        MD
      end

      wiring = ChapterWiring.new(skills_root: dir)
      orphans = wiring.orphaned_chapters
      assert_includes orphans, "chapter-b.md",
        "expected the dropped-load-line fixture to report chapter-b.md as orphaned; got #{orphans.inspect}"
      refute_includes orphans, "chapter-a.md",
        "chapter-a.md has a consumer line in the fixture and must not be reported orphaned"
    end
  end

  # Can-fail proof (intent 208): a load line pointing at a chapter file that
  # does not exist must be reported as a dangling reference, naming it.
  def test_unresolved_reference_check_can_fail
    Dir.mktmpdir("plastic-chapter-wiring-dangling-test") do |dir|
      build_fixture_tree(dir) do |skill_md|
        File.write(skill_md, <<~MD)
          ---
          name: plastic-consumer
          description: fixture consumer
          user-invocable: true
          ---

          Read `../plastic-conventions/references/chapter-a.md` for chapter A doctrine.
          Read `../plastic-conventions/references/chapter-missing.md` for doctrine that does not exist.
        MD
      end

      wiring = ChapterWiring.new(skills_root: dir)
      dangling = wiring.unresolved_references
      assert_includes dangling, "chapter-missing.md",
        "expected the fixture's dangling load line to report chapter-missing.md; got #{dangling.inspect}"
      refute_includes dangling, "chapter-a.md",
        "chapter-a.md resolves to a real fixture file and must not be reported dangling"
    end
  end
end
