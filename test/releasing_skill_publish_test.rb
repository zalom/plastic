# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# The release doctrine names the publish workflow.
class ReleasingSkillPublishTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  AGENTS_PATH = File.join(REPO, "AGENTS.md")

  def test_agents_md_describes_the_publish_workflow
    content = File.read(AGENTS_PATH)
    assert_includes content, "publish.yml",
      "AGENTS.md's release doctrine line must name the publish workflow, not describe a release made by hand"
  end
end

# The CI workflow test.yml triggers on `alpha` and on manual dispatch, and runs
# the same `ruby bin/test` the release gate runs.
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

  def test_ci_checks_the_packaged_executable_from_the_release_builder
    run = steps.find { |s| s["name"] == "Verify the packaged executable" }["run"]

    assert_includes run, "ruby scripts/build-release"
    assert_includes run, "PLASTIC_ACCEPTANCE_BIN=\"$release/package/bin/plastic\" ruby bin/test --only test/cli/release_contract_test.rb"
  end

  def test_ci_sets_up_no_node
    refute_match(/\bnpm\b|setup-node/, File.read(PATH))
  end
end
