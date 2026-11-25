# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# The owner's release flow of 24 November 2026: beta holds the tested line and takes its fixes,
# alpha takes new work, and main gets beta on the owner's word, with no freeze.
class ReleaseFlowGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  RELEASE_BRANCHES = %w[alpha beta main].freeze
  RULE_PAGES = ["AGENTS.md", "CONTRIBUTING.md", "README.md", *Dir["docs/*.md", "docs/contributing/*.md", "docs/usage/*.md", base: ROOT]].freeze
  LIGHT_TRUNK = /light trunk|one trunk|frozen until|stays frozen|Frozen while|until the shaping ends|snapshot of `alpha`|ships behind a config switch/i

  def read(path) = File.read(File.join(ROOT, path))

  def triggers
    workflow = YAML.safe_load(read(".github/workflows/test.yml"))
    workflow.fetch(true) { workflow.fetch("on") }
  end

  def test_the_test_workflow_runs_on_a_push_to_each_release_branch
    assert_equal [], RELEASE_BRANCHES - triggers.fetch("push").fetch("branches")
  end

  def test_the_test_workflow_runs_on_a_pull_request_to_each_release_branch
    assert_equal [], RELEASE_BRANCHES - triggers.fetch("pull_request").fetch("branches")
  end

  def test_no_rule_page_names_the_light_trunk_the_freeze_or_the_switch_rule
    named = RULE_PAGES.to_h { |path| [path, read(path).scan(LIGHT_TRUNK)] }.reject { |_, words| words.empty? }

    assert_equal({}, named)
  end

  def test_the_release_lines_page_names_the_clean_install_and_the_update_from_the_previous_release
    page = read("docs/release-lines.md")

    assert_includes page, "## Prove a release before the push"
    assert_includes page, "ruby bin/build-release"
    assert_includes page, "share/active/scripts/install-release"
  end
end
