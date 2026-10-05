# frozen_string_literal: true

require "digest"
require "openssl"
require_relative "archive"

module InstallerRelease
  # A downloaded Ruby archive held to its pin.
  class RubyArchive
    def initialize(path, pin)
      @path = path
      @pin = pin
    end

    def check
      bytes = File.size(path)
      size = pin.fetch("size")
      raise VerificationError, "the Ruby archive has #{bytes} bytes, not the pinned #{size}" unless bytes == size
      raise VerificationError, "the Ruby archive does not match its pinned SHA-256" unless digest_matches?

      Archive.new(path, limits: Rubies::LIMITS).entry_names
    end

    private

    attr_reader :path, :pin

    def digest_matches? = OpenSSL.secure_compare(pin.fetch("sha256"), Digest::SHA256.file(path).hexdigest)
  end
end
