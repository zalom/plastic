# frozen_string_literal: true

require "fileutils"
require_relative "../errors"
require_relative "release_files"

module Plastic
  module Installations
    # A directory holding one release's three files, for development only.
    class LocalSource
      DEVELOPMENT = "development mode: reading releases from %s; this claims no release trust"

      def initialize(directory)
        @directory = directory
      end

      def newest(_channel)
        ReleaseFiles.new(directory).manifest.dig("release", "version")
      rescue VerificationError => error
        raise Failed, "cannot read the local release folder #{directory}: #{error.message}"
      end

      def files(_version, target)
        ReleaseFiles::NAMES.each { |name| FileUtils.cp(File.join(directory, name), File.join(target, name)) }
        ReleaseFiles.new(target)
      end

      def notices = [format(DEVELOPMENT, directory)]

      private

      attr_reader :directory
    end
  end
end
