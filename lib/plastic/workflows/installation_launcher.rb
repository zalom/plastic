# frozen_string_literal: true

module Plastic
  module Workflows
    # Finds the first `plastic` on PATH and checks that it is the launcher
    # the installer links into the bin directory.
    class InstallationLauncher
      def initialize(bin:, path:)
        @bin = bin
        @path = path
      end

      def check
        return InstallationHealth::Check.new("launcher:", found, nil) if found == expected

        InstallationHealth::Check.new("launcher:", found ? "#{found} runs first, not #{expected}" : "not on PATH",
          "put #{bin} first on PATH; the installer links the launcher there")
      end

      private

      attr_reader :bin, :path

      def expected = File.join(bin, "plastic")

      def found
        @found ||= path.split(File::PATH_SEPARATOR).map { |entry| File.join(entry, "plastic") }.find { |file| File.executable?(file) }
      end
    end
  end
end
