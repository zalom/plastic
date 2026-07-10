# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/skill_lint"

# SkillLintTest (intent 85b): proves each of SkillLint's five checks fires
# RED on a deliberate fixture failure and GREEN on a compliant skill, then
# guards the shipped `skills/` tree with a no-skip-list live-tree assertion
# (172-style: no hardcoded skip-list, no per-skill exception).
#
# Hermetic and DI: every red/green proof builds an isolated temp `skills_dir`
# (symlinked subset of test/fixtures/skill_lint/) so each proof runs against
# exactly the fixture(s) it names, never the whole fixture set at once. No
# ambient session id, no network, no eval.
class SkillLintTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)
  FIXTURES_ROOT = File.join(REPO, "test", "fixtures", "skill_lint")

  # Build an isolated temp skills_dir containing ONLY the named fixture
  # subdirectories (symlinked, not copied, for speed), run SkillLint over it,
  # and clean up. Guarantees each proof is scoped to exactly its fixture(s).
  def lint(*names)
    dir = Dir.mktmpdir("skill-lint-test")
    names.each { |name| File.symlink(File.join(FIXTURES_ROOT, name), File.join(dir, name)) }
    SkillLint.new(skills_dir: dir).run
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  def test_fixtures_exist
    %w[pass fail_body_lines fail_body_tokens fail_yaml fail_name fail_user_invocable
       fail_bare_pointer fail_bare_pointer_paragraph_leak fail_bare_pointer_bullet_list
       fail_orphan fail_depth].each do |name|
      assert File.file?(File.join(FIXTURES_ROOT, name, "SKILL.md")),
        "expected fixture test/fixtures/skill_lint/#{name}/SKILL.md to exist"
    end
  end

  def test_pass_fixture_is_green_on_all_five_checks
    result = lint("pass")
    assert result.ok?, "pass/ fixture should be clean: #{result.violations.inspect}"
  end

  def test_fail_body_lines_trips_body_budget_line_subcheck_only
    result = lint("fail_body_lines")
    refute result.ok?
    checks = result.violations.map { |v| v[:check] }.uniq
    assert_equal ["body-budget"], checks, "fail_body_lines should trip ONLY body-budget"
    record = result.violations_for("body-budget").find { |v| v[:rule].include?("500 lines") }
    refute_nil record, "expected a body-budget record citing the 500-line sub-check"
  end

  def test_fail_body_tokens_trips_body_budget_token_subcheck_only
    result = lint("fail_body_tokens")
    refute result.ok?
    checks = result.violations.map { |v| v[:check] }.uniq
    assert_equal ["body-budget"], checks, "fail_body_tokens should trip ONLY body-budget"
    record = result.violations_for("body-budget").find { |v| v[:rule].include?("token") }
    refute_nil record, "expected a body-budget record citing the token sub-check (word-based estimate must BITE)"
    refute result.violations_for("body-budget").any? { |v| v[:rule].include?("500 lines") },
      "fail_body_tokens is under 500 lines; the line sub-check must not also fire"
  end

  def test_fail_yaml_trips_frontmatter_validity_yaml_subcheck
    result = lint("fail_yaml")
    refute result.ok?
    checks = result.violations.map { |v| v[:check] }.uniq
    assert_equal ["frontmatter-validity"], checks, "fail_yaml should trip ONLY frontmatter-validity"
    record = result.violations_for("frontmatter-validity").find { |v| v[:rule].include?("YAML.safe_load") }
    refute_nil record, "expected a frontmatter-validity record citing YAML.safe_load"
  end

  # Correction 1: the name-check rule is `name == "plastic-#{dir}"`, not a bare
  # basename compare (which would go red on all 34 live skills). fail_name's
  # dir is `fail_name` with a frontmatter name lacking the `plastic-` prefix,
  # mirroring the 158 `name: lock` bug shape, and must trip red.
  def test_fail_name_trips_frontmatter_validity_name_subcheck
    result = lint("fail_name")
    refute result.ok?
    checks = result.violations.map { |v| v[:check] }.uniq
    assert_equal ["frontmatter-validity"], checks, "fail_name should trip ONLY frontmatter-validity"
    record = result.violations_for("frontmatter-validity").find { |v| v[:rule].include?("plastic-<directory>") }
    refute_nil record, "expected a frontmatter-validity record citing the name: plastic-<directory> rule"
    assert_match(/plastic-fail_name/, record[:message], "message should name the expected plastic-<dir> value")
  end

  def test_fail_user_invocable_trips_frontmatter_validity_user_invocable_subcheck
    result = lint("fail_user_invocable")
    refute result.ok?
    checks = result.violations.map { |v| v[:check] }.uniq
    assert_equal ["frontmatter-validity"], checks, "fail_user_invocable should trip ONLY frontmatter-validity"
    record = result.violations_for("frontmatter-validity").find { |v| v[:rule].include?("user-invocable") }
    refute_nil record, "expected a frontmatter-validity record citing the user-invocable rule"
  end

  def test_fail_bare_pointer_trips_bare_pointer_check_only
    result = lint("fail_bare_pointer")
    refute result.ok?
    checks = result.violations.map { |v| v[:check] }.uniq
    assert_equal ["bare-pointer"], checks, "fail_bare_pointer should trip ONLY bare-pointer"
    record = result.violations_for("bare-pointer").first
    assert_equal "fail_bare_pointer", record[:skill]
    refute_nil record[:line], "bare-pointer violation should cite the first bare mention's line"
  end

  # Regression guard (reviewer-found defect, fixed same session): bound_mention?
  # must not test binding keywords/purpose clauses against the WHOLE paragraph
  # block, or an unrelated sentence's incidental "to"/"for" (ordinary
  # prepositions) launders a genuinely bare pointer as bound. This fixture's
  # only mention of foo.md is a bare `See \`references/foo.md\`.` sentence
  # sitting next to an unrelated sentence containing "related to" (before the
  # fix this wrongly reported ok? with 0 violations; after the fix it trips).
  def test_fail_bare_pointer_paragraph_leak_trips_bare_pointer_check_only
    result = lint("fail_bare_pointer_paragraph_leak")
    refute result.ok?, "an incidental to/for in a NEIGHBORING sentence must not launder a bare pointer as bound"
    checks = result.violations.map { |v| v[:check] }.uniq
    assert_equal ["bare-pointer"], checks, "fail_bare_pointer_paragraph_leak should trip ONLY bare-pointer"
    record = result.violations_for("bare-pointer").first
    assert_equal "fail_bare_pointer_paragraph_leak", record[:skill]
  end

  # Regression guard (second reviewer-found defect, fixed same session): a
  # bullet list has no terminal .!? between items, so the unit-splitter must
  # also break on list-item starts, not just sentence punctuation. Without
  # that, a whole multi-bullet "## References" list collapses into ONE unit
  # whose bound siblings ("Read ... for ...") launder a genuinely bare bullet
  # among them. This fixture has alpha/gamma bound and beta bare; only beta
  # may trip.
  def test_fail_bare_pointer_bullet_list_trips_bare_pointer_check_only
    result = lint("fail_bare_pointer_bullet_list")
    refute result.ok?, "a bare bullet among bound siblings in the same list must not be laundered as bound"
    checks = result.violations.map { |v| v[:check] }.uniq
    assert_equal ["bare-pointer"], checks, "fail_bare_pointer_bullet_list should trip ONLY bare-pointer"
    records = result.violations_for("bare-pointer")
    assert_equal 1, records.size, "only the bare beta.md bullet should trip, not the bound alpha/gamma siblings"
    assert_match(/beta\.md/, records.first[:message])
  end

  def test_fail_orphan_trips_orphan_files_check_only
    result = lint("fail_orphan")
    refute result.ok?
    checks = result.violations.map { |v| v[:check] }.uniq
    assert_equal ["orphan-files"], checks, "fail_orphan should trip ONLY orphan-files"
    record = result.violations_for("orphan-files").first
    assert_match(/unrouted\.md/, record[:file])
  end

  def test_fail_depth_trips_references_depth_check_only
    result = lint("fail_depth")
    refute result.ok?
    checks = result.violations.map { |v| v[:check] }.uniq
    assert_equal ["references-depth"], checks, "fail_depth should trip ONLY references-depth"
    record = result.violations_for("references-depth").first
    assert_match(%r{sub/deep\.md}, record[:file])
  end

  # Live-tree guard (172-style, NO skip-list): the shipped skills/ tree must be
  # clean on every check. This is the standard-honesty gate: a real violation
  # here is a finding to adjudicate (fix the skill or the rule), never a
  # skip-list entry, and never a weakened check.
  def test_live_skills_tree_is_clean
    result = SkillLint.new(skills_dir: File.join(REPO, "skills")).run

    if result.violations.any?
      dump = result.violations.map { |v| "  #{v[:check]} #{v[:skill]} #{v[:file]}:#{v[:line]}: #{v[:message]}" }.join("\n")
      flunk "skills/ tree has #{result.violations.size} SkillLint violation(s), no skip-list allowed:\n#{dump}"
    end

    assert result.ok?
  end
end
