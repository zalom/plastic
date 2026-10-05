# frozen_string_literal: true

require_relative "flat_share"
require_relative "rubies"

module InstallerRelease
  # The entries the installer makes in the share: the releases, the Rubies,
  # the links, the lock and stopped downloads. Removing them leaves every
  # other file, and the share with it while such a file stays.
  class ShareEntries
    def initialize(share)
      @share = share
    end

    def remove
      FlatShare.new(share, Releases.new(share)).migrate
      names.each { |name| Rubies.remove(File.join(share, name)) }
      Dir.rmdir(share) if Dir.empty?(share)
    end

    private

    attr_reader :share

    def names = Dir.children(share).select { |name| FlatShare::KEPT.include?(name) || name.match?(FlatShare::DOWNLOADS) }
  end
end
