# frozen_string_literal: true

require "fileutils"
require_relative "../installations/release_feed"
require_relative "../installations/release_source"
require_relative "../installations/share"

module Plastic
  module Workflows
    # The activated releases under the share directory, read only, and the
    # release source that offers newer ones: GitHub, or a local directory that
    # a development run names in PLASTIC_LOCAL_RELEASE. A newer release is
    # downloaded and checked into the share's download folder; installing it
    # is the active release's install-release script.
    class ReleaseUpdate
      CHANNELS = { "stable" => "latest", "beta" => "beta", "alpha" => "alpha" }.freeze

      def self.of(context)
        scope = context.scope
        share = scope.setting("PLASTIC_SHARE", File.join(scope.home, ".local", "share", "plastic"))
        new(share, Installations::ReleaseSource.for(scope.setting("PLASTIC_LOCAL_RELEASE")))
      end

      def initialize(share, source)
        @share = share
        @source = source
      end

      def installed = Installations::Share.new(share)

      def active_version = installed.active_version

      def notices = source.notices

      def newer_release(channel = nil)
        active = active_version
        newest = source.newest(CHANNELS.fetch(channel) { Installations::ReleaseFeed.channel_of(active) })
        newest if newest && Installations::ReleaseFeed.newer?(newest, active)
      end

      def download(version)
        directory = File.join(share, "download")
        fetch(version, directory)
        directory
      rescue
        FileUtils.rm_rf(directory)
        raise
      end

      private

      attr_reader :share, :source

      def fetch(version, directory)
        FileUtils.rm_rf(directory)
        FileUtils.mkdir_p(directory)
        source.files(version, directory).verify
      end
    end
  end
end
