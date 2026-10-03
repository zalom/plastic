# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../../installer_release"

module Plastic
  module Workflows
    # The activated releases under the share directory, and the release
    # source that offers newer ones: GitHub, or a local directory that a
    # development run names in PLASTIC_LOCAL_RELEASE.
    class ReleaseUpdate
      DEVELOPMENT = "development mode: reading releases from %s; this claims no release trust"

      attr_reader :activation

      def self.of(context, bundle: InstallerRelease::Bundle.new)
        scope = context.scope
        local = scope.setting("PLASTIC_LOCAL_RELEASE")
        share = scope.setting("PLASTIC_SHARE", File.join(scope.home, ".local", "share", "plastic"))
        new(share, InstallerRelease::ReleaseSource.for(local), bundle)
      end

      def initialize(share, source, bundle)
        @share = share
        @source = source
        @bundle = bundle
        @activation = InstallerRelease::Activation.new(home: share)
      end

      def active_version = activation.active_version

      def warning(context)
        context.print(format(DEVELOPMENT, context.scope.setting("PLASTIC_LOCAL_RELEASE"))) unless source.trusted?
      end

      def newer_release
        active = active_version
        newest = source.newest(InstallerRelease::Manifest.identity(active).fetch("channel"))
        newest if newest && InstallerRelease::ReleaseFeed.newer?(newest, active)
      end

      def activate(version)
        FileUtils.mkdir_p(share)
        Dir.mktmpdir("plastic-download-", share) do |directory|
          files = source.files(version, directory).verify
          InstallerRelease::ReleaseInstall.new(home: share, bundle: bundle)
            .call(archive: files.archive, manifest: files.manifest, expected: InstallerRelease::Manifest.identity(version))
        end
      end

      private

      attr_reader :share, :source, :bundle
    end
  end
end
