# frozen_string_literal: true

require "digest"
require "json"
require "openssl"

module InstallerRelease
  # The three files of one release in a directory: the archive, its
  # checksum file and the manifest. The archive is checked against the
  # checksum file before anything reads it.
  class ReleaseFiles
    ARCHIVE = "plastic.tgz"
    CHECKSUM = "plastic.tgz.sha256"
    MANIFEST = "plastic.manifest.json"
    NAMES = [ARCHIVE, CHECKSUM, MANIFEST].freeze

    def initialize(directory, digest: Digest::SHA256)
      @directory = directory
      @digest = digest
    end

    def archive = path(ARCHIVE)

    def verify
      sum, name = File.read(path(CHECKSUM)).split
      raise VerificationError, "checksum file does not name #{ARCHIVE}" unless name.to_s.delete_prefix("*") == ARCHIVE
      raise VerificationError, "archive checksum does not match" unless OpenSSL.secure_compare(sum.to_s, digest.file(archive).hexdigest)

      self
    end

    def manifest
      JSON.parse(File.read(path(MANIFEST)))
    rescue JSON::ParserError
      raise VerificationError, "manifest does not parse"
    end

    private

    attr_reader :directory, :digest

    def path(name)
      file = File.join(directory, name)
      raise VerificationError, "release is missing #{name}" unless File.file?(file)

      file
    end
  end
end
