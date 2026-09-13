# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# PublishWorkflowTest (intent 347, S1): pins the shape of
# .github/workflows/publish.yml, the trusted-publishing (OIDC) workflow that
# replaces a laptop-held npm token with a short-lived, per-run credential.
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

  def publish_job
    parsed["jobs"]["publish"]
  end

  def steps
    publish_job["steps"]
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

  def publish_step
    step_named("Publish to npm")
  end

  def has_pull_request?(trigger_map)
    trigger_map.key?("pull_request")
  end

  def test_workflow_lives_at_the_registered_path
    assert File.file?(PATH), "expected .github/workflows/publish.yml to exist; npm keys the trusted publisher on this exact filename"
  end

  def test_workflow_parses_as_yaml
    assert_kind_of Hash, Psych.safe_load(File.read(PATH), aliases: false)
  end

  def test_trigger_map_is_found_under_the_yaml_true_key
    refute_empty triggers, "expected a non-empty trigger map under parsed[true]"
    assert_nil parsed["on"], "parsed[\"on\"] must be nil; Psych resolves the bare key to true"
  end

  def test_triggers_on_version_tags_only
    assert_equal ["v*"], triggers["push"]["tags"]
    refute triggers["push"].key?("branches"), "a branch push must not trigger a publish"
  end

  def test_supports_manual_dispatch_with_a_required_tag_input
    assert triggers["workflow_dispatch"]["inputs"]["tag"]["required"]
  end

  def test_has_no_pull_request_trigger
    refute has_pull_request?(triggers), "a pull_request trigger would let a fork PR obtain an id-token"
  end

  def test_pull_request_detection_catches_a_real_trigger
    fixture = Psych.safe_load("on:\n  pull_request: {}\n", aliases: false)
    assert has_pull_request?(triggers(fixture)), "the predicate must report a real pull_request trigger, or the row above proves nothing"
  end

  def test_publish_job_requests_an_id_token
    assert_equal({ "contents" => "read", "id-token" => "write" }, publish_job["permissions"])
  end

  def test_workflow_permissions_default_to_read
    assert_equal({ "contents" => "read" }, parsed["permissions"])
  end

  def test_runs_on_a_github_hosted_runner
    assert_equal "ubuntu-latest", publish_job["runs-on"]
  end

  def test_sets_up_ruby
    refute_nil step_using("ruby/setup-ruby@v1"), "expected a ruby/setup-ruby@v1 step"
  end

  def test_sets_up_node_with_the_npm_registry
    step = step_using("actions/setup-node@v7")
    refute_nil step, "expected an actions/setup-node@v7 step"
    assert_equal "https://registry.npmjs.org", step["with"]["registry-url"]
  end

  def test_installs_a_current_npm
    assert steps.any? { |s| s["run"].to_s.include?("npm install -g npm@latest") },
      "expected a step that installs a current npm before the guard runs"
  end

  def test_guard_step_passes_the_npm_version
    refute_nil guard_step, "expected a step with id: guard"
    assert_includes guard_step["run"], '--npm-version "$(npm --version)"'
  end

  def test_guard_runs_before_the_publish
    guard_index = steps.index(guard_step)
    publish_index = steps.index(publish_step)
    refute_nil publish_index, "expected a step named 'Publish to npm'"
    assert guard_index < publish_index, "the guard must run before the publish step"
  end

  # D7, resolved 2026-09-09 against evidence. test.yml ran on a hosted runner
  # for the first time since 2026-08-25, on the alpha merge of this intent:
  # https://github.com/zalom/plastic/actions/runs/34335126166. It came back red
  # with three failures that have nothing to do with the release path and
  # everything to do with test hermeticity on Linux: session_start_test reads a
  # real ~/.plastic/scripts/read-config that no runner has, capture_hook_test
  # does not rewrite its heartbeat there, and maintenance_run_test's teardown
  # cannot rmdir a .git/objects tree. Gating a publish on that suite would
  # relocate the alpha.18 stall from the laptop to the runner, the exact failure
  # this intent exists to remove, so the suite step comes out of the publish job.
  # The suite still gates the release where it always did, as release.verify, run
  # before the tag is cut. Pin the absence so restoring the step is a deliberate
  # act taken with the runner green, not an accident.
  def test_does_not_run_the_full_suite_in_the_publish_job
    suite_step = steps.find { |s| s["run"].to_s.strip == "ruby bin/test" }
    assert_nil suite_step,
      "the publish job must not run the suite while it is red on a hosted runner (D7); " \
      "restore this step only once test.yml is green on alpha"
  end

  # The dispatch-or-pushed tag reaches the guard through env:, not interpolated
  # straight into the run: string, so an untrusted value cannot land in a
  # shell context even though nothing escalates today (pushing a v* tag or
  # dispatching the workflow both already need write access; the job still
  # holds id-token: write, so this is belt-and-suspenders) (review fix 4).
  def test_guard_reads_the_dispatch_tag_or_the_pushed_tag
    assert_equal "${{ inputs.tag || github.ref_name }}", guard_step["env"]["TAG"]
    assert_includes guard_step["run"], '--tag "$TAG"'
    refute_includes guard_step["run"], "inputs.tag",
      "the tag expression must reach the shell through env:, never interpolated straight into run:"
  end

  def test_checkout_uses_the_dispatch_tag_or_the_pushed_ref
    checkout = step_using("actions/checkout@v7")
    refute_nil checkout, "expected an actions/checkout@v7 step"
    assert_equal "${{ inputs.tag || github.ref }}", checkout["with"]["ref"]
  end

  def test_publish_passes_provenance
    assert_includes publish_step["run"], "--provenance"
  end

  def test_publish_passes_public_access
    assert_includes publish_step["run"], "--access public"
  end

  def test_publish_tag_is_exactly_the_guard_output
    run_line = publish_step["run"]
    assert_includes run_line, '--tag "${{ steps.guard.outputs.dist_tag }}"'
    refute_match(/\b(alpha|beta|latest)\b/, run_line,
      "the publish run: line must carry no literal channel name; ubuntu-latest and npm@latest legitimately appear elsewhere in the file")
  end

  def test_publishes_are_serialized
    concurrency = parsed["concurrency"]
    refute_nil concurrency, "expected a top-level concurrency block"
    assert_equal "publish-${{ github.ref }}", concurrency["group"]
    assert_equal false, concurrency["cancel-in-progress"]
  end
end
