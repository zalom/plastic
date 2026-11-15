# frozen_string_literal: true

require "rubygems/version"
require_relative "release_files"

module Plastic
  module Installations
    # Picks the newest release on a channel from the GitHub release list,
    # counting only releases that carry all three release files.
    module ReleaseFeed
      module_function

      def newest(releases, channel) = versions(releases).select { |version| channel_of(version) == channel }.max_by { |version| order(version) }

      def versions(releases) = releases.select { |release| complete?(release) }.map { |release| release.fetch("tag_name").delete_prefix("v") }

      def newer?(candidate, current) = (order(candidate) <=> order(current)) == 1

      def order(version) = Gem::Version.new(version)

      def channel_of(version) = version[/-(alpha|beta)\b/, 1] || "latest"

      def complete?(release) = (ReleaseFiles::NAMES - release.fetch("assets").map { |asset| asset["name"] }).empty?
    end
  end
end
