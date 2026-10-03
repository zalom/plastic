# frozen_string_literal: true

require "fileutils"
require_relative "../../installer_release"

module Plastic
  module Workflows
    # The releases under the share directory and the launcher linked to
    # them, which an uninstall removes once no agent stays registered. A
    # share without releases and a launcher Plastic does not own stay.
    class ReleaseRemoval
      FOREIGN = "%s is not Plastic's launcher; it stays"

      def self.of(context)
        scope = context.scope
        home = scope.home
        new(share: scope.setting("PLASTIC_SHARE", File.join(home, ".local", "share", "plastic")),
          launcher: File.join(scope.setting("PLASTIC_BIN", File.join(home, ".local", "bin")), "plastic"))
      end

      def initialize(share:, launcher:)
        @share = share
        @link = InstallerRelease::LauncherLink.new(launcher, share)
      end

      def planned = [(link.path if link.linked?), (share if releases?)].compact

      def call
        removed = planned
        removed.each { |path| FileUtils.rm_rf(path) }
        removed.map { |path| ["removed:", path] } + kept
      end

      private

      attr_reader :share, :link

      def releases? = File.directory?(File.join(share, "releases")) || File.file?(File.join(share, "VERSION"))

      def kept = link.ours? ? [] : [["kept:", format(FOREIGN, link.path)]]
    end
  end
end
