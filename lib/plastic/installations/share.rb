# frozen_string_literal: true

require "rubygems/version"
require_relative "launcher_link"

module Plastic
  module Installations
    # The share directory of an installation, read only: the release the
    # active pointer names, the one before it, the releases on disk and the
    # launcher link that points into the share.
    class Share
      def initialize(root)
        @root = root
      end

      def active_path = File.join(root, "active")

      def active_version = Share.version_at(active_path)

      def previous_version = Share.version_at(File.join(root, "previous"))

      def versions
        releases = File.join(root, "releases")
        File.directory?(releases) ? Dir.children(releases).sort_by { |version| Gem::Version.new(version) } : []
      end

      def release? = File.directory?(File.join(root, "releases")) || File.file?(File.join(root, "VERSION"))

      def launcher_link(path) = LauncherLink.new(path, root)

      def self.version_at(path)
        file = File.join(path, "VERSION")
        File.file?(file) ? File.read(file).strip : nil
      end

      private

      attr_reader :root
    end
  end
end
