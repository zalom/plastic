# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

require_relative "../scripts/lib/skill_lint"

# ReleasingSkillPublishTest (intent 347, S4): the releasing skill gains a
# second post-push action, `npm_publish_workflow`, alongside the `npm_publish`
# it already has. The skill is generic and shipped to every Plastic user
# (`skills/` is in package.json `files`), so it keeps the `<package>`
# placeholder and never names `@zalom/plastic`.
class ReleasingSkillPublishTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  SKILL_PATH = File.join(REPO, "skills", "releasing", "SKILL.md")
  PROMOTION_PATH = File.join(REPO, "skills", "releasing", "references", "promotion-and-tagging.md")
  AGENTS_PATH = File.join(REPO, "AGENTS.md")

  def skill_body
    @skill_body ||= File.read(SKILL_PATH)
  end

  # Returns the text between a heading matching heading_regex and the next
  # heading of the same or a shallower level, exclusive of both headings.
  # Heading detection is suspended inside fenced code blocks, so a bash
  # comment such as "# Alpha pre-release" inside a ```bash fence is never
  # mistaken for a markdown heading and does not truncate the section early.
  def section_body(markdown, heading_regex)
    lines = markdown.lines
    start_idx = lines.index { |l| l =~ heading_regex }
    return "" unless start_idx

    level = lines[start_idx][/\A#+/].length
    body = []
    in_fence = false
    lines[(start_idx + 1)..-1].each do |line|
      in_fence = !in_fence if line.start_with?("```")
      break if !in_fence && line =~ /\A(#+)\s/ && Regexp.last_match(1).length <= level

      body << line
    end
    body.join
  end

  def workflow_section
    section_body(skill_body, /^#+\s+`npm_publish_workflow`\s*$/)
  end

  def local_publish_section
    section_body(skill_body, /^#+\s+`npm_publish`\s*$/)
  end

  def test_releasing_skill_implements_npm_publish_workflow
    assert_match(/^#+\s+`npm_publish_workflow`\s*$/, skill_body,
      "expected a heading for the npm_publish_workflow action")
  end

  def test_releasing_skill_keeps_the_local_npm_publish_action
    refute_empty local_publish_section, "expected the npm_publish section to still exist"
    assert_match(/^\s*npm publish --access public\b/, local_publish_section,
      "npm_publish must keep publishing locally for every other project")
  end

  def test_releasing_skill_names_no_concrete_package
    refute_includes skill_body, "@zalom/plastic",
      "the shipped skill must keep the <package> placeholder, never a concrete package name"
  end

  def test_workflow_action_requires_confirming_a_run_exists
    refute_empty workflow_section, "expected an npm_publish_workflow section"
    list_at = workflow_section.index("gh run list")
    watch_at = workflow_section.index("gh run watch")
    refute_nil list_at, "expected the section to name gh run list"
    refute_nil watch_at, "expected the section to name gh run watch"
    assert list_at < watch_at, "the run must be confirmed to exist before it is watched"
  end

  def test_workflow_action_verifies_the_dist_tag
    assert_includes workflow_section, "npm view <package> dist-tags"
  end

  def test_releasing_skill_keeps_the_dist_tag_table
    rows = workflow_section.lines.map(&:strip).select { |l| l.start_with?("|") }
    rows.reject! { |l| l =~ /^\|[\s:-]+\|[\s:-]+\|$/ } # drop the separator row
    rows.reject! { |l| l.downcase.include?("version contains") } # drop the header row
    assert_equal 3, rows.size,
      "expected three table rows mapping a version shape to its channel, not bare prose: #{rows.inspect}"
    assert rows.any? { |r| r.include?("alpha") }
    assert rows.any? { |r| r.include?("beta") }
    assert rows.any? { |r| r.include?("latest") }
  end

  # Anchored on fenced-code-block context, not line start: a leading backtick
  # (an inline code span reintroducing the command as `npm publish ...`
  # rather than a bare shell line) defeats a ^\s*npm publish\b anchor while
  # still instructing the session to publish locally. promotion-and-tagging.md:50
  # legitimately carries an inline `npm publish --access public --tag <channel>`
  # span in prose documenting the OTHER action (npm_publish); that line sits
  # outside any fence and must still be accepted (review fix 3).
  def test_promotion_reference_has_no_local_publish_command
    content = File.read(PROMOTION_PATH)
    offenders = []
    in_fence = false
    content.each_line do |line|
      in_fence = !in_fence if line.start_with?("```")
      offenders << line if in_fence && line.include?("npm publish")
    end
    assert_empty offenders,
      "the promotion reference must not tell the session to publish locally inside a fenced code block: #{offenders.inspect}"
  end

  def test_promotion_reference_keeps_its_rules
    content = File.read(PROMOTION_PATH)
    assert_includes content, "npm dist-tag add"
    assert_includes content, "gh release edit"
    assert_includes content, "Linear only"
    assert_includes content, "Cannot skip channels"
  end

  def test_agents_md_describes_the_publish_workflow
    content = File.read(AGENTS_PATH)
    assert_includes content, "publish.yml",
      "AGENTS.md's release doctrine line must name the publish workflow, not just describe a hand-run npm publish"
  end

  def test_skill_lint_is_clean
    result = SkillLint.new(skills_dir: File.join(REPO, "skills")).run
    assert_empty result.violations, result.violations.map { |v| "#{v[:skill]}: #{v[:message]}" }.join("\n")
  end
end

# CiWorkflowTest (intent 347, S6): test.yml has run green on `main` only, and
# `main` has never received the 2.0 alpha line, so the suite has not proven
# itself on a hosted runner in its current form since 2026-08-25. Extends the
# trigger to `alpha` and to manual dispatch, and points it at the same
# `ruby bin/test` the release gate runs (D7).
class CiWorkflowTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  PATH = File.join(REPO, ".github", "workflows", "test.yml")

  def parsed
    @parsed ||= Psych.safe_load(File.read(PATH), aliases: false)
  end

  def triggers
    parsed["on"] || parsed[true] || {}
  end

  def steps
    parsed["jobs"]["test"]["steps"]
  end

  def test_ci_runs_on_the_alpha_branch
    assert_includes triggers["push"]["branches"], "alpha"
    assert_includes triggers["pull_request"]["branches"], "alpha"
  end

  def test_ci_runs_bin_test
    assert steps.any? { |s| s["run"].to_s.strip == "ruby bin/test" },
      "expected a step that runs exactly ruby bin/test, the configured release.verify"
  end

  def test_ci_supports_manual_dispatch
    assert triggers.key?("workflow_dispatch"), "expected workflow_dispatch among the triggers"
  end
end
