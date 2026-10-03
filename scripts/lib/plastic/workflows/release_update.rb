# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../../installer_release"

module Plastic
  module Workflows
    # The activated releases under the share directory, and the release
    # source that offers newer ones: GitHub, or a local directory that a
    # development run names in PLASTIC_LOCAL_RELEASE. Each switch syncs the
    # home files of the release it switches to.
    class ReleaseUpdate
      CHANNELS = { "stable" => "latest", "beta" => "beta", "alpha" => "alpha" }.freeze

      def self.of(context, bundle: InstallerRelease::Bundle.new)
        scope = context.scope
        share = scope.setting("PLASTIC_SHARE", File.join(scope.home, ".local", "share", "plastic"))
        new(share, InstallerRelease::ReleaseSource.for(scope.setting("PLASTIC_LOCAL_RELEASE")), bundle, home_sync(scope, share))
      end

      def self.chosen_channels(context) = CHANNELS.keys.select { |name| context.public_send(name) }

      def self.home_sync(scope, share)
        user_home = scope.home
        launcher = File.join(scope.setting("PLASTIC_BIN", File.join(user_home, ".local", "bin")), "plastic")
        home = InstallerRelease::ManagedHome.new(plastic_home: scope.plastic_home, user_home: user_home, launcher: launcher)
        InstallerRelease::HomeSync.new(share: share, home: home)
      end

      def initialize(share, source, bundle, sync = InstallerRelease::NoSync)
        @share = share
        @source = source
        @bundle = bundle
        @sync = sync
      end

      def activation = InstallerRelease::Activation.new(home: share, sync: sync)

      def active_version = activation.active_version

      def notices = source.notices

      def newer_release(channel = nil)
        active = active_version
        newest = source.newest(CHANNELS.fetch(channel) { InstallerRelease::Manifest.identity(active).fetch("channel") })
        newest if newest && InstallerRelease::ReleaseFeed.newer?(newest, active)
      end

      def activate(version)
        FileUtils.mkdir_p(share)
        Dir.mktmpdir("plastic-download-", share) do |directory|
          files = source.files(version, directory).verify
          InstallerRelease::ReleaseInstall.new(home: share, bundle: bundle, sync: sync)
            .call(archive: files.archive, manifest: files.manifest, expected: InstallerRelease::Manifest.identity(version))
        end
      end

      private

      attr_reader :share, :source, :bundle, :sync
    end
  end
end
