# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# ReleasingSkillPublishTest (intent 347, S4): the release doctrine names the publish workflow.
class ReleasingSkillPublishTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  AGENTS_PATH = File.join(REPO, "AGENTS.md")

  def test_agents_md_describes_the_publish_workflow
    content = File.read(AGENTS_PATH)
    assert_includes content, "publish.yml",
      "AGENTS.md's release doctrine line must name the publish workflow, not just describe a hand-run npm publish"
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
