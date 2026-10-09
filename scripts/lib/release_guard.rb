# encoding: UTF-8
# frozen_string_literal: true

require "json"

# Mechanical guard for stable-cut version preconditions. Reads
# the version from package.json, the one repo version file, and, when a
# stable/latest cut is declared, checks that it carries no pre-release
# suffix. Pure function over an injected path: no ENV reads, no eval, no
# global-config seam, hermetically testable and safe to call from both the
# release workflow and the test suite.
#
# Deliberately does not check a repo VERSION file: none exists in this repo.
# VERSION is an install-target artifact written fresh from package.json at
# install/update time (scripts/lib/installer_core.rb); it cannot drift
# independently because it is never committed.
module ReleaseGuard
  Result = Struct.new(:ok, :version, :prerelease_suffix, keyword_init: true) do
    def ok?
      ok
    end
  end

  # stable: true gates a stable/latest cut (rejects any pre-release suffix);
  # false allows a suffix.
  def self.check(package_json:, stable:)
    version = read_version(package_json)
    suffix = version&.match(/-(.+)\z/)&.captures&.first

    Result.new(ok: !version.nil? && !(stable && suffix), version: version, prerelease_suffix: suffix)
  end

  # The channel each release branch makes. scripts/release-check compares it
  # with the channel InstallerRelease::Manifest.identity reads from the version.
  CHANNELS = {"alpha" => "alpha", "beta" => "beta", "main" => "latest"}.freeze

  def self.read_version(path)
    JSON.parse(File.read(path))["version"]
  rescue Errno::ENOENT, JSON::ParserError
    nil
  end
  private_class_method :read_version
end
