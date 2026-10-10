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

      # The home sync's output joins the call's printed lines, so it prints in
      # the order it happened.
      Printed = Data.define(:context) do
        def puts(text) = text.each_line(chomp: true) { |line| context.print(line) }
      end

      def self.of(context, bundle: InstallerRelease::Bundle.new)
        scope = context.scope
        share = scope.setting("PLASTIC_SHARE", File.join(scope.home, ".local", "share", "plastic"))
        sync = home_sync(scope, share, Printed.new(context))
        choice = InstallerRelease::RubyChoice.new(home: share, override: scope.setting("PLASTIC_RUBY", ""))
        new(share, InstallerRelease::ReleaseSource.for(scope.setting("PLASTIC_LOCAL_RELEASE")), sync,
          InstallerRelease::ReleaseInstall.new(home: share, bundle: bundle, sync: sync, choice: choice))
      end

      def self.home_sync(scope, share, out)
        user_home = scope.home
        launcher = File.join(scope.setting("PLASTIC_BIN", File.join(user_home, ".local", "bin")), "plastic")
        home = InstallerRelease::ManagedHome.new(plastic_home: scope.plastic_home, user_home: user_home, launcher: launcher)
        InstallerRelease::HomeSync.new(share: share, home: home, out: out)
      end

      def initialize(share, source, sync, install)
        @share = share
        @source = source
        @sync = sync
        @install = install
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
          install.call(archive: files.archive, manifest: files.manifest, expected: InstallerRelease::Manifest.identity(version))
        end
      end

      private

      attr_reader :share, :source, :sync, :install
    end
  end
end
