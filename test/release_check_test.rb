# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"

require_relative "../scripts/lib/release_guard"

# ReleaseGuardDistTagTest (intent 347, S2): the channel-derivation rule gets
# exactly one implementation, ReleaseGuard.dist_tag, shared by the workflow's
# guard script and this test. Getting it wrong pulls every stable user onto
# an alpha at their next `plastic update`.
class ReleaseGuardDistTagTest < Minitest::Test
  def test_dist_tag_reads_alpha_beta_and_latest
    assert_equal "alpha", ReleaseGuard.dist_tag("2.0.0-alpha.19")
    assert_equal "beta", ReleaseGuard.dist_tag("2.0.0-beta.1")
    assert_equal "latest", ReleaseGuard.dist_tag("2.0.0")
  end

  def test_dist_tag_never_returns_latest_for_an_unknown_suffix
    refute_equal "latest", ReleaseGuard.dist_tag("2.0.0-rc.1")
  end
end

# ReleaseCheckCliTest (intent 347, S2): scripts/release-check, a thin CLI
# over ReleaseGuard.check plus the tag, npm-floor, and $GITHUB_OUTPUT checks
# the library does not have. Every fixture is a Dir.mktmpdir nested
# .claude-plugin/ layout, matching the real repo shape, and every test passes
# --root; no test reads or writes the real repository.
#
# ReleaseGuard.check degrades a missing file to a mismatch rather than
# raising, so a flat tmpdir fixture would make every rejection test pass for
# the wrong reason, over a CLI that reads nothing. The nested builder below
# and the positive-control test guard against that.
class ReleaseCheckCliTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  SCRIPT = File.join(REPO, "scripts", "release-check")

  def build_repo(dir, version:, plugin_version: nil, marketplace_version: nil)
    plugin_version ||= version
    marketplace_version ||= version

    File.write(File.join(dir, "package.json"), JSON.generate({ "version" => version }))
    FileUtils.mkdir_p(File.join(dir, ".claude-plugin"))
    File.write(
      File.join(dir, ".claude-plugin", "plugin.json"),
      JSON.generate({ "version" => plugin_version })
    )
    File.write(
      File.join(dir, ".claude-plugin", "marketplace.json"),
      JSON.generate({ "plugins" => [{ "name" => "plastic", "version" => marketplace_version }] })
    )
  end

  def run_cli(root:, tag:, npm_version:, github_output: nil, extra_args: [])
    args = ["--tag", tag, "--npm-version", npm_version, "--root", root]
    args += ["--github-output", github_output] if github_output
    args += extra_args
    Open3.capture3(RbConfig.ruby, SCRIPT, *args)
  end

  def test_accepts_a_matching_tag_and_agreeing_files
    Dir.mktmpdir do |dir|
      build_repo(dir, version: "2.0.0-alpha.19")
      _out, err, status = run_cli(root: dir, tag: "v2.0.0-alpha.19", npm_version: "11.5.1")
      assert status.success?, "expected exit 0, got stderr: #{err}"
    end
  end

  def test_rejects_a_tag_that_disagrees_with_package_json
    Dir.mktmpdir do |dir|
      build_repo(dir, version: "2.0.0-alpha.19")
      _out, err, status = run_cli(root: dir, tag: "v2.0.0-alpha.20", npm_version: "11.5.1")
      refute status.success?
      assert_equal 1, status.exitstatus
      assert_includes err, "2.0.0-alpha.20"
      assert_includes err, "2.0.0-alpha.19"
    end
  end

  def test_accepts_a_full_ref_as_the_tag
    Dir.mktmpdir do |dir|
      build_repo(dir, version: "2.0.0-alpha.19")
      _out, err, status = run_cli(root: dir, tag: "refs/tags/v2.0.0-alpha.19", npm_version: "11.5.1")
      assert status.success?, "expected exit 0, got stderr: #{err}"
    end
  end

  def test_rejects_disagreeing_version_files
    Dir.mktmpdir do |dir|
      build_repo(dir, version: "2.0.0-alpha.19", plugin_version: "2.0.0-alpha.18")
      _out, err, status = run_cli(root: dir, tag: "v2.0.0-alpha.19", npm_version: "11.5.1")
      refute status.success?
      assert_equal 1, status.exitstatus
      assert_includes err, ".claude-plugin/plugin.json"
    end
  end

  def test_rejects_an_npm_below_the_floor
    Dir.mktmpdir do |dir|
      build_repo(dir, version: "2.0.0-alpha.19")
      _out, err, status = run_cli(root: dir, tag: "v2.0.0-alpha.19", npm_version: "11.5.0")
      refute status.success?, "expected 11.5.0 to fail the floor: #{err}"
      assert_equal 1, status.exitstatus

      _out2, err2, status2 = run_cli(root: dir, tag: "v2.0.0-alpha.19", npm_version: "11.5.1")
      assert status2.success?, "expected 11.5.1 to pass the floor: #{err2}"
    end
  end

  def test_compares_npm_versions_numerically
    Dir.mktmpdir do |dir|
      build_repo(dir, version: "2.0.0-alpha.19")
      _out, err, status = run_cli(root: dir, tag: "v2.0.0-alpha.19", npm_version: "11.10.0")
      assert status.success?, "11.10.0 must sort above the 11.5.1 floor numerically: #{err}"
    end
  end

  # Both a coerced-to-zero read and the degenerate-input guard exit 1 here, so
  # exit status alone does not pin which branch caught it. Assert the
  # diagnostic message too: "empty or not numeric" comes only from the
  # degenerate-input check, never from the floor comparison, which would
  # instead say "is below the 11.5.1 floor" (review fold-in 1).
  def test_rejects_an_empty_or_non_numeric_npm_version
    Dir.mktmpdir do |dir|
      build_repo(dir, version: "2.0.0-alpha.19")

      _out, err, status = run_cli(root: dir, tag: "v2.0.0-alpha.19", npm_version: "")
      refute status.success?, "an empty npm version must not pass: #{err}"
      assert_equal 1, status.exitstatus
      assert_match(/empty or not numeric/, err, "expected the degenerate-input diagnostic, not a floor-comparison message")

      _out2, err2, status2 = run_cli(root: dir, tag: "v2.0.0-alpha.19", npm_version: "not-a-version")
      refute status2.success?, "a non-numeric npm version must not pass: #{err2}"
      assert_equal 1, status2.exitstatus
      assert_match(/empty or not numeric/, err2, "expected the degenerate-input diagnostic, not a floor-comparison message")
    end
  end

  def test_writes_dist_tag_and_version_to_github_output
    Dir.mktmpdir do |dir|
      build_repo(dir, version: "2.0.0-alpha.19")
      output_path = File.join(dir, "github_output")
      File.write(output_path, "")
      _out, err, status = run_cli(root: dir, tag: "v2.0.0-alpha.19", npm_version: "11.5.1", github_output: output_path)
      assert status.success?, "expected exit 0, got stderr: #{err}"
      written = File.read(output_path)
      assert_includes written, "version=2.0.0-alpha.19"
      assert_includes written, "dist_tag=alpha"
    end
  end

  def test_appends_to_github_output_without_clobbering
    Dir.mktmpdir do |dir|
      build_repo(dir, version: "2.0.0-alpha.19")
      output_path = File.join(dir, "github_output")
      File.write(output_path, "other=1\n")
      _out, err, status = run_cli(root: dir, tag: "v2.0.0-alpha.19", npm_version: "11.5.1", github_output: output_path)
      assert status.success?, "expected exit 0, got stderr: #{err}"
      written = File.read(output_path)
      assert_includes written, "other=1"
      assert_includes written, "version=2.0.0-alpha.19"
      assert_includes written, "dist_tag=alpha"
    end
  end

  def test_reports_usage_for_an_unknown_flag
    Dir.mktmpdir do |dir|
      build_repo(dir, version: "2.0.0-alpha.19")
      _out, _err, status = run_cli(
        root: dir, tag: "v2.0.0-alpha.19", npm_version: "11.5.1",
        extra_args: ["--bogus-flag"]
      )
      assert_equal 2, status.exitstatus
    end
  end
end
