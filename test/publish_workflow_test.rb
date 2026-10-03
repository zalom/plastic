# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# PublishWorkflowTest (intent 347, S1): pins the shape of
# .github/workflows/publish.yml, the workflow that makes the tag and the
# GitHub release install.sh downloads. Since the npm retirement of
# 2026-10-03 it talks to no package registry.
#
# Psych resolves the bare YAML key `on` to boolean `true` under YAML 1.1
# resolution, so the trigger map lives at parsed[true], not parsed["on"].
# Every test reads triggers through the `triggers` helper rather than
# indexing "on" directly, and one test pins the reason the helper exists.
class PublishWorkflowTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  PATH = File.join(REPO, ".github", "workflows", "publish.yml")

  def parsed
    @parsed ||= Psych.safe_load(File.read(PATH), aliases: false)
  end

  def triggers(doc = parsed)
    doc["on"] || doc[true] || {}
  end

  def release_job
    parsed["jobs"]["release"]
  end

  def steps
    release_job["steps"]
  end

  def step_using(uses_prefix)
    steps.find { |s| s["uses"].to_s.start_with?(uses_prefix) }
  end

  def step_named(name)
    steps.find { |s| s["name"] == name }
  end

  def guard_step
    steps.find { |s| s["id"] == "guard" }
  end

  def build_step
    step_named("Build the release files")
  end

  def release_step
    step_named("Create the tag and the GitHub release")
  end

  def has_pull_request?(trigger_map)
    trigger_map.key?("pull_request")
  end

  def test_workflow_lives_at_the_registered_path
    assert File.file?(PATH), "expected .github/workflows/publish.yml to exist; the release history and the branch rules name this exact filename"
  end

  def test_workflow_parses_as_yaml
    assert_kind_of Hash, Psych.safe_load(File.read(PATH), aliases: false)
  end

  def test_trigger_map_is_found_under_the_yaml_true_key
    refute_empty triggers, "expected a non-empty trigger map under parsed[true]"
    assert_nil parsed["on"], "parsed[\"on\"] must be nil; Psych resolves the bare key to true"
  end

  def test_triggers_on_a_push_to_each_channel_branch
    assert_equal %w[alpha beta main], triggers["push"]["branches"]
  end

  def test_a_pushed_tag_starts_nothing
    refute triggers["push"].key?("tags")
  end

  def test_supports_manual_dispatch
    assert triggers.key?("workflow_dispatch")
  end

  def test_has_no_pull_request_trigger
    refute has_pull_request?(triggers), "a pull_request trigger would let a fork PR run a job that can write the repository"
  end

  def test_pull_request_detection_catches_a_real_trigger
    fixture = Psych.safe_load("on:\n  pull_request: {}\n", aliases: false)

    assert has_pull_request?(triggers(fixture)), "the predicate must report a real pull_request trigger, or the row above proves nothing"
  end

  def test_release_job_writes_contents_and_asks_for_no_id_token
    assert_equal({ "contents" => "write" }, release_job["permissions"])
  end

  def test_workflow_permissions_default_to_read
    assert_equal({ "contents" => "read" }, parsed["permissions"])
  end

  def test_runs_on_a_github_hosted_runner
    assert_equal "ubuntu-latest", release_job["runs-on"]
  end

  def test_sets_up_ruby
    refute_nil step_using("ruby/setup-ruby@v1"), "expected a ruby/setup-ruby@v1 step"
  end

  def test_sets_up_no_node
    assert_nil step_using("actions/setup-node"), "the release needs no Node and no package registry"
  end

  def test_no_step_talks_to_npm
    refute_match(/\bnpm\b|npmjs|registry-url/, File.read(PATH))
    assert_nil release_job["environment"], "the npm environment went with the npm publish"
  end

  def test_guard_step_reads_only_the_branch
    refute_nil guard_step, "expected a step with id: guard"
    assert_equal 'ruby scripts/release-check --branch "$BRANCH" --github-output "$GITHUB_OUTPUT"', guard_step["run"].strip
  end

  def test_guard_runs_before_the_build_and_the_build_before_the_release
    refute_nil build_step, "expected a step named 'Build the release files'"
    assert_operator steps.index(guard_step), :<, steps.index(build_step)
    assert_operator steps.index(build_step), :<, steps.index(release_step)
  end

  def test_the_suite_runs_before_the_guard
    suite_index = steps.index { |s| s["run"].to_s.strip == "ruby bin/test" }

    refute_nil suite_index, "expected a step that runs ruby bin/test"
    assert_operator suite_index, :<, steps.index(guard_step)
  end

  # The dispatch-or-pushed tag reaches the guard through env:, not interpolated
  # straight into the run: string, so an untrusted value cannot land in a
  # shell context even though nothing escalates today (pushing a v* tag or
  # dispatching the workflow both already need write access; the job still
  # holds contents: write, so this is belt-and-suspenders) (review fix 4).
  def test_guard_reads_the_pushed_branch_through_env
    assert_equal "${{ github.ref_name }}", guard_step["env"]["BRANCH"]
    assert_includes guard_step["run"], '--branch "$BRANCH"'
  end

  def test_publish_waits_for_an_unreleased_version
    assert_equal "unreleased", release_job["needs"]
    assert_equal "needs.unreleased.outputs.tag != ''", release_job["if"]
  end

  def test_an_existing_tag_leaves_the_tag_output_empty
    run = parsed["jobs"]["unreleased"]["steps"].last["run"]

    assert_includes run, 'git ls-remote --exit-code --tags origin "refs/tags/$tag"'
  end

  def test_the_release_carries_the_three_install_files_at_the_pushed_commit
    assert_includes release_step["run"],
      'gh release create "$TAG" release/plastic.tgz release/plastic.tgz.sha256 release/plastic.manifest.json --target "$GITHUB_SHA"'
  end

  def test_the_build_uses_the_builder_the_tests_and_the_install_job_use
    assert_equal 'ruby scripts/build-release --version "$VERSION" --directory release', build_step["run"].strip
    assert_equal "${{ steps.guard.outputs.version }}", build_step["env"]["VERSION"]
  end

  def test_the_release_kind_is_exactly_the_guard_channel
    assert_equal "${{ steps.guard.outputs.channel == 'latest' }}", release_step["env"]["STABLE"]
    refute_match(/\b(alpha|beta|latest)\b/, release_step["run"], "the release run: line must carry no literal channel name")
  end

  def test_every_channel_makes_the_github_release
    assert_empty steps.filter_map { |step| step["name"] if step["if"] }, "the build and the release run on alpha, beta and main alike"
  end

  def test_publishes_are_serialized
    concurrency = parsed["concurrency"]

    refute_nil concurrency, "expected a top-level concurrency block"
    assert_equal "publish-${{ github.ref }}", concurrency["group"]
    refute concurrency["cancel-in-progress"]
  end
end
