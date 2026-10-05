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
    # stay. The closing lines come from what was known before each removal,
    # never from the disk after it, since the kernel and its Ruby go with the
    # share.
    class ReleaseRemoval
      FOREIGN = "%s is not Plastic's launcher; it stays"
      UNKNOWN = "%s holds files Plastic did not make; they stay"

      def self.of(context)
        scope = context.scope
        home = scope.home
        new(share: scope.setting("PLASTIC_SHARE", File.join(home, ".local", "share", "plastic")),
          launcher: File.join(scope.setting("PLASTIC_BIN", File.join(home, ".local", "bin")), "plastic"))
      end

      def initialize(share:, launcher:)
        @share = share
        @link = InstallerRelease::LauncherLink.new(launcher, share)
        @entries = InstallerRelease::ShareEntries.new(share)
      end

      def planned = [(link.path if link.linked?), (share if releases?)].compact

      def call
        removed = planned
        FileUtils.rm_f(removed - [share])
        closing_lines(removed, (removed & [share]).reject { entries.remove })
      end

      private

      attr_reader :share, :link, :entries

      def releases? = File.directory?(File.join(share, "releases")) || File.file?(File.join(share, "VERSION"))

      def closing_lines(removed, stayed) = (removed - stayed).map { |path| ["removed:", path] } + kept(stayed)

      def kept(stayed)
        foreign = link.ours? ? [] : [["kept:", format(FOREIGN, link.path)]]
        foreign + stayed.map { |path| ["kept:", format(UNKNOWN, path)] }
      end
    end
  end
end
