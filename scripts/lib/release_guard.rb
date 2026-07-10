# encoding: UTF-8
# frozen_string_literal: true

require "json"

# Mechanical guard for stable-cut version preconditions (intent 155). Checks
# that the three repo version files agree on one version string, and, when a
# stable/latest cut is declared, that the resolved version carries no
# pre-release suffix. Pure function over injected paths: no ENV reads, no
# eval, no global-config seam, hermetically testable and safe to call from
# both the release workflow and the test suite.
#
# Deliberately does not check a repo VERSION file: none exists in this repo.
# VERSION is an install-target artifact written fresh from package.json at
# install/update time (scripts/lib/installer_core.rb); it cannot drift
# independently because it is never committed.
module ReleaseGuard
  Result = Struct.new(:ok, :version, :mismatches, :prerelease_suffix, keyword_init: true) do
    def ok?
      ok
    end
  end

  # package_json / plugin_json / marketplace_json: paths to the three repo
  # version files. stable: true gates a stable/latest cut (rejects any
  # pre-release suffix); false allows a suffix, only agreement is checked.
  def self.check(package_json:, plugin_json:, marketplace_json:, stable:)
    versions = {
      "package.json" => read_version(package_json) { |data| data["version"] },
      ".claude-plugin/plugin.json" => read_version(plugin_json) { |data| data["version"] },
      ".claude-plugin/marketplace.json" => read_version(marketplace_json) { |data| plastic_plugin_version(data) },
    }

    canonical = versions["package.json"]
    mismatches = versions.reject { |_file, version| version && version == canonical }.keys

    suffix = canonical&.match(/-(.+)\z/)&.captures&.first
    prerelease_violation = stable && !suffix.nil?

    Result.new(
      ok: mismatches.empty? && !prerelease_violation,
      version: canonical,
      mismatches: mismatches,
      prerelease_suffix: suffix
    )
  end

  def self.plastic_plugin_version(data)
    plugins = Array(data["plugins"])
    plugin = plugins.find { |p| p["name"] == "plastic" } || plugins.first
    plugin && plugin["version"]
  end
  private_class_method :plastic_plugin_version

  def self.read_version(path)
    data = JSON.parse(File.read(path))
    yield data
  rescue Errno::ENOENT, JSON::ParserError
    nil
  end
  private_class_method :read_version
end
