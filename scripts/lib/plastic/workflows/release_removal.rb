# frozen_string_literal: true

require "fileutils"
require_relative "../../installer_release"
require_relative "../../installer_release/share_entries"

module Plastic
  module Workflows
    # The releases and Rubies under the share directory and the launcher
    # linked to them, which an uninstall removes once no agent stays
    # registered. Only the entries Plastic makes go: other files in the
    # share, a share without releases, and a launcher Plastic does not own
    # stay.
    class ReleaseRemoval
      FOREIGN = "%s is not Plastic's launcher; it stays"
      UNKNOWN = "%s holds files Plastic did not make; they stay"

      def self.of(context)
        scope = context.scope
        home = scope.home
        new(share: scope.setting("PLASTIC_SHARE", File.join(home, ".local", "share", "plastic")),
          launcher: File.join(scope.setting("PLASTIC_BIN", File.join(home, ".local", "bin")), "plastic"))
      end

      def self.gone?(path) = !File.exist?(path) && !File.symlink?(path)

      def initialize(share:, launcher:)
        @share = share
        @link = InstallerRelease::LauncherLink.new(launcher, share)
      end

      def planned = [(link.path if link.linked?), (share if releases?)].compact

      def call
        removed = planned
        launcher = link.path
        FileUtils.rm_f(launcher) if removed.include?(launcher)
        InstallerRelease::ShareEntries.new(share).remove if removed.include?(share)
        rows(removed)
      end

      private

      attr_reader :share, :link

      def releases? = File.directory?(File.join(share, "releases")) || File.file?(File.join(share, "VERSION"))

      def rows(removed)
        gone, stayed = removed.partition { |path| self.class.gone?(path) }
        gone.map { |path| ["removed:", path] } + kept(stayed)
      end

      def kept(stayed)
        foreign = link.ours? ? [] : [["kept:", format(FOREIGN, link.path)]]
        foreign + stayed.map { |path| ["kept:", format(UNKNOWN, path)] }
      end
    end
  end
end
