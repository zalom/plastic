# frozen_string_literal: true

require "digest"
require "json"

module InstallerRelease
  class VerificationError < StandardError; end

  class Manifest
    REQUIRED_TOP_LEVEL_KEYS = %w[schema release archive ruby compatibility].freeze
    REQUIRED_RELEASE_KEYS = %w[tag version channel repository platform architecture].freeze
    REQUIRED_ARCHIVE_KEYS = %w[name sha256].freeze

    def self.build(archive:, release:, ruby_requirement: ">= 4.0.0")
      release_data = release.merge("repository" => official_url(release.fetch("tag")))
      { "schema" => 1, "release" => release_data,
        "archive" => { "name" => File.basename(archive), "sha256" => Digest::SHA256.file(archive).hexdigest },
        "ruby" => { "requirement" => ruby_requirement }, "compatibility" => { "store_layout" => "current" } }
    end

    def self.write(path, **arguments)
      value = build(**arguments)
      File.write(path, JSON.pretty_generate(value) + "\n")
      value
    end

    def self.validate!(manifest, archive:, expected_release:)
      required_keys!(manifest, REQUIRED_TOP_LEVEL_KEYS, "manifest")
      release = manifest.fetch("release")
      archive_info = manifest.fetch("archive")
      validate_sections!(release, archive_info)
      validate_release!(release, expected_release)
      validate_archive!(archive_info, archive)
      true
    end

    def self.validate_sections!(release, archive_info)
      required_keys!(release, REQUIRED_RELEASE_KEYS, "release")
      required_keys!(archive_info, REQUIRED_ARCHIVE_KEYS, "archive")
    end

    def self.validate_release!(release, expected)
      expected.each { |key, value| fail!("release #{key} does not match") unless release[key] == value }
      tag = release.fetch("tag")
      fail!("release tag does not match version") unless tag == "v#{release.fetch("version")}"
      fail!("release repository is not official HTTPS") unless release["repository"] == official_url(tag)
    end

    def self.validate_archive!(archive_info, archive)
      fail!("archive name does not match") unless archive_info["name"] == File.basename(archive)
      digest = Digest::SHA256.file(archive).hexdigest
      fail!("archive checksum does not match") unless secure_equal?(archive_info["sha256"], digest)
    end

    def self.required_keys!(value, keys, name)
      fail!("#{name} is not an object") unless value.is_a?(Hash)
      missing = keys.reject { |key| value.key?(key) }
      fail!("#{name} is missing #{missing.join(", ")}") unless missing.empty?
    end

    def self.fail!(message)
      raise VerificationError, message
    end

    def self.official_url(tag)
      "https://github.com/zalom/plastic/releases/tag/#{tag}"
    end

    def self.secure_equal?(left, right)
      return false unless left.is_a?(String) && left.bytesize == right.bytesize

      left.bytes.zip(right.bytes).map { |left_byte, right_byte| left_byte ^ right_byte }.reduce(0, :|).zero?
    end
  end
end
