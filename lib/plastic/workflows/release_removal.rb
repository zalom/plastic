# frozen_string_literal: true

require "fileutils"
require_relative "../installations/share"

module Plastic
  module Workflows
    # The releases under the share directory and the launcher
    # linked to them, which an uninstall removes once no agent stays
    # registered. Only the entries Plastic makes go: other files in the
    # share, a share without releases, and a launcher Plastic does not own
    # stay. The closing lines come from what was known before each removal,
    # never from the disk after it, since the kernel and its Ruby go with the
    # share.
    class ReleaseRemoval
      FOREIGN = "%s is not Plastic's launcher; it stays"
      UNKNOWN = "%s holds files Plastic did not make; they stay"
      OWN = %w[releases rubies active previous download INSTALL.lock activation VERSION].freeze
      STAGES = /\Aplastic-(?:stage|download)-/

      def self.of(context)
        scope = context.scope
        home = scope.home
        new(share: scope.setting("PLASTIC_SHARE", File.join(home, ".local", "share", "plastic")),
          launcher: File.join(scope.setting("PLASTIC_BIN", File.join(home, ".local", "bin")), "plastic"))
      end

      def initialize(share:, launcher:)
        @share = share
        @installed = Installations::Share.new(share)
        @link = @installed.launcher_link(launcher)
      end

      def planned = [(link.path if link.linked?), (share if installed.release?)].compact

      def call
        removed = planned
        FileUtils.rm_f(removed - [share])
        closing_lines(removed, (removed & [share]).reject { remove_share })
      end

      private

      attr_reader :share, :installed, :link

      def remove_share
        empty = own_entries.size == Dir.children(share).size
        own_entries.each { |name| remove_entry(File.join(share, name)) }
        Dir.rmdir(share) if empty
        empty
      end

      def own_entries = Dir.children(share).select { |name| OWN.include?(name) || name.match?(STAGES) }.partition { |name| name != "rubies" }.flatten

      def remove_entry(path)
        FileUtils.chmod_R("u+w", path, force: true)
        FileUtils.rm_rf(path)
      end

      def closing_lines(removed, stayed) = (removed - stayed).map { |path| ["removed:", path] } + kept(stayed)

      def kept(stayed)
        foreign = link.ours? ? [] : [["kept:", format(FOREIGN, link.path)]]
        foreign + stayed.map { |path| ["kept:", format(UNKNOWN, path)] }
      end
    end
  end
end
