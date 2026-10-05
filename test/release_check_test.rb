# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class ReleaseCheckTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/release-check", __dir__)

  def setup
    @root = Dir.mktmpdir("plastic-release-check")
    @output = File.join(@root, "github-output")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_main_releases_a_stable_version_on_the_latest_channel
    _out, err, status = check("2.0.4", "--branch", "main")

    assert_predicate status, :success?, err
    assert_equal "version=2.0.4\nchannel=latest\ntag=v2.0.4\n", File.read(@output)
  end

  def test_alpha_releases_an_alpha_version_on_the_alpha_channel
    _out, err, status = check("2.0.4-alpha.1", "--branch", "alpha")

    assert_predicate status, :success?, err
    assert_includes File.read(@output), "channel=alpha\n"
  end

  def test_a_branch_refuses_a_version_of_another_channel
    _out, err, status = check("2.0.4", "--branch", "alpha")

    assert_equal 1, status.exitstatus
    assert_includes err, "branch alpha releases alpha, and version 2.0.4 is latest"
  end

  def test_main_refuses_a_version_with_an_unknown_suffix
    _out, err, status = check("2.0.4-rc.1", "--branch", "main")

    assert_equal 1, status.exitstatus
    assert_includes err, "carries the pre-release suffix -rc.1"
  end

  def test_the_tag_must_match_the_version
    _out, err, status = check("2.0.4", "--tag", "v2.0.5")

    assert_equal 1, status.exitstatus
    assert_includes err, "tag v2.0.5 does not match package.json version 2.0.4"
  end

  def test_a_call_without_a_branch_or_tag_is_a_usage_error
    _out, err, status = check("2.0.4")

    assert_equal 2, status.exitstatus
    assert_includes err, "usage: release-check"
  end

  private

  def check(version, *arguments)
    File.write(File.join(@root, "package.json"), JSON.generate("version" => version))
    Open3.capture3("ruby", SCRIPT, *arguments, "--github-output", @output, "--root", @root)
  end
end
