# frozen_string_literal: true

require "json"

module Plastic
  module Installations
    # The version a package carries: its VERSION file, else the version of its
    # package.json.
    class PackageVersion
      def initialize(root)
        @root = root
      end

      def call
        file = File.join(@root, "VERSION")
        return File.read(file).strip if File.exist?(file)

        json = File.join(@root, "package.json")
        return JSON.parse(File.read(json))["version"] if File.exist?(json)

        raise "cannot determine the package version: neither #{json} nor #{file} exists"
      end
    end
  end
end
