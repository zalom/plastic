# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/lib/release_guard"

class ReleaseGuardTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("release-guard")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_package_json_alone_names_the_version
    result = ReleaseGuard.check(package_json: package("2.0.4-alpha.1"), stable: false)

    assert_predicate result, :ok?
    assert_equal "2.0.4-alpha.1", result.version
  end

  def test_a_stable_cut_refuses_a_prerelease_suffix
    result = ReleaseGuard.check(package_json: package("2.0.4-beta.2"), stable: true)

    refute_predicate result, :ok?
    assert_equal "beta.2", result.prerelease_suffix
  end

  def test_an_unreadable_package_json_fails
    result = ReleaseGuard.check(package_json: File.join(@root, "missing.json"), stable: false)

    refute_predicate result, :ok?
    assert_nil result.version
  end

  private

  def package(version)
    path = File.join(@root, "package.json")
    File.write(path, JSON.generate("version" => version))
    path
  end
end
