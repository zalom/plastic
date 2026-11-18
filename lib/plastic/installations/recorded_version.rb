# frozen_string_literal: true

require "fileutils"

module Plastic
  module Installations
    # The VERSION file in an agent's folder: the version the last install wrote.
    class RecordedVersion
      def initialize(dir)
        @path = File.join(dir, "VERSION")
      end

      def installed? = File.exist?(@path)

      def read = installed? ? File.read(@path).strip : nil

      def write(version)
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, "#{version}\n")
        @path
      end
    end
  end
end
