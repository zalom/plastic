# frozen_string_literal: true

require "digest"
require "json"
require "openssl"

module InstallerRelease
  class VerificationError < StandardError; end

  # The JSON file published beside the archive. It binds the archive's name
  # and SHA-256 to one release of the official repository.
  class Manifest
    REQUIRED_KEYS = {
      "manifest" => %w[schema release archive ruby compatibility],
      "release" => %w[tag version channel repository platform architecture],
      "archive" => %w[name sha256]
    }.freeze

    def self.build(archive:, release:, ruby_requirement: ">= 4.0.0")
      release_data = release.merge("repository" => official_url(release.fetch("tag")))
      { "schema" => 1, "release" => release_data,
        "archive" => { "name" => File.basename(archive), "sha256" => Digest::SHA256.file(archive).hexdigest },
        "ruby" => { "requirement" => ruby_requirement }, "compatibility" => { "store_layout" => "current" } }
    end

    def self.write(path, **arguments)
      value = build(**arguments)
      File.write(path, "#{JSON.pretty_generate(value)}\n")
      value
    end

    def self.check(manifest, archive:, expected_release:)
      ManifestCheck.new(manifest, archive).call(expected_release)
    end

    def self.official_url(tag) = "https://github.com/zalom/plastic/releases/tag/#{tag}"

    def self.identity(version)
      channel = version[/-(alpha|beta)\b/, 1] || "latest"
      { "version" => version, "tag" => "v#{version}", "channel" => channel }
    end
  end

  # One check of a parsed manifest against the archive on disk and the
  # release the installer asked for. It raises with the first problem.
  class ManifestCheck
    def initialize(manifest, archive)
      @manifest = manifest
      @archive = archive
    end

    def call(expected)
      check_sections
      check_release(expected)
      check_archive(manifest.fetch("archive"))
      true
    end

    private

    attr_reader :archive, :manifest

    def check_sections
      required("manifest", manifest)
      %w[release archive].each { |section| required(section, manifest.fetch(section)) }
    end

    def required(section, value)
      fail_with("#{section} is not an object") unless value.is_a?(Hash)
      missing = Manifest::REQUIRED_KEYS.fetch(section).reject { |key| value.key?(key) }
      fail_with("#{section} is missing #{missing.join(", ")}") unless missing.empty?
    end

    def release = manifest.fetch("release")

    def check_release(expected)
      expected.each { |key, value| fail_with("release #{key} does not match") unless release[key] == value }
      tag = release.fetch("tag")
      fail_with("release tag does not match version") unless tag == "v#{release.fetch("version")}"
      fail_with("release repository is not official HTTPS") unless release["repository"] == Manifest.official_url(tag)
    end

    def check_archive(section)
      fail_with("archive name does not match") unless section["name"] == File.basename(archive)
      fail_with("archive checksum does not match") unless digest_matches?(section["sha256"].to_s)
    end

    def digest_matches?(given) = OpenSSL.secure_compare(given, Digest::SHA256.file(archive).hexdigest)

    def fail_with(message)
      raise VerificationError, message
    end
  end
end
