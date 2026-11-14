# frozen_string_literal: true

require "fileutils"
require_relative "../../../scripts/lib/installer_release"

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
        new(share, InstallerRelease::ReleaseSource.for(scope.setting("PLASTIC_LOCAL_RELEASE")))
      end

      def initialize(share, source)
        @share = share
        @source = source
      end

      def activation = InstallerRelease::Activation.new(home: share)

      def active_version = activation.active_version

      def notices = source.notices

      def newer_release(channel = nil)
        active = active_version
        newest = source.newest(CHANNELS.fetch(channel) { InstallerRelease::Manifest.identity(active).fetch("channel") })
        newest if newest && InstallerRelease::ReleaseFeed.newer?(newest, active)
      end

      def download(version)
        directory = File.join(share, "download")
        empty(directory)
        source.files(version, directory).verify
        directory
      rescue InstallerRelease::VerificationError
        empty(directory)
        raise
      end

      private

      attr_reader :share, :source

      def empty(directory)
        FileUtils.rm_rf(directory)
        FileUtils.mkdir_p(directory)
      end
    end
  end
end
