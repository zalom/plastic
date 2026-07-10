# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require_relative "../scripts/lib/release_guard"

# Mechanical guard test (intent 155). Hermetic: every fixture lives under
# Dir.mktmpdir, no ENV reads, no eval, no global-config seam.
class ReleaseGuardTest < Minitest::Test
  def test_ok_when_all_three_files_agree_and_no_suffix_required
    with_fixtures("1.1.0", "1.1.0", "1.1.0") do |paths|
      result = ReleaseGuard.check(**paths, stable: true)
      assert result.ok?
      assert_equal "1.1.0", result.version
      assert_empty result.mismatches
      assert_nil result.prerelease_suffix
    end
  end

  def test_not_ok_when_a_file_disagrees
    with_fixtures("1.1.0", "1.1.0", "1.0.9") do |paths|
      result = ReleaseGuard.check(**paths, stable: true)
      refute result.ok?
      assert_includes result.mismatches, ".claude-plugin/marketplace.json"
    end
  end

  def test_not_ok_when_stable_declared_but_version_carries_a_suffix
    with_fixtures("1.2.0-beta.1", "1.2.0-beta.1", "1.2.0-beta.1") do |paths|
      result = ReleaseGuard.check(**paths, stable: true)
      refute result.ok?
      assert_equal "beta.1", result.prerelease_suffix
    end
  end

  def test_ok_when_beta_declared_with_a_suffix
    with_fixtures("1.2.0-beta.1", "1.2.0-beta.1", "1.2.0-beta.1") do |paths|
      result = ReleaseGuard.check(**paths, stable: false)
      assert result.ok?
      assert_equal "beta.1", result.prerelease_suffix
    end
  end

  def test_missing_file_reports_as_a_mismatch_not_a_crash
    Dir.mktmpdir do |dir|
      package_json = File.join(dir, "package.json")
      plugin_json = File.join(dir, "missing-plugin.json")
      marketplace_json = File.join(dir, "missing-marketplace.json")
      File.write(package_json, JSON.generate("version" => "1.1.0"))

      result = ReleaseGuard.check(
        package_json: package_json,
        plugin_json: plugin_json,
        marketplace_json: marketplace_json,
        stable: true
      )
      refute result.ok?
      assert_includes result.mismatches, ".claude-plugin/plugin.json"
      assert_includes result.mismatches, ".claude-plugin/marketplace.json"
    end
  end

  private

  def with_fixtures(package_version, plugin_version, marketplace_version)
    Dir.mktmpdir do |dir|
      package_json = File.join(dir, "package.json")
      plugin_json = File.join(dir, "plugin.json")
      marketplace_json = File.join(dir, "marketplace.json")

      File.write(package_json, JSON.generate("version" => package_version))
      File.write(plugin_json, JSON.generate("version" => plugin_version))
      File.write(
        marketplace_json,
        JSON.generate("plugins" => [{ "name" => "plastic", "version" => marketplace_version }])
      )

      yield(package_json: package_json, plugin_json: plugin_json, marketplace_json: marketplace_json)
    end
  end
end
