# frozen_string_literal: true

require_relative "flat_share"
require_relative "rubies"

module InstallerRelease
  # The entries the installer makes in the share: the releases, the Rubies,
  # the links, the lock and stopped downloads. Removing them leaves every
  # other file, and the share with it while such a file stays. The Rubies go
  # last, since an uninstall runs on one of them, and whether the share goes
  # is known before the first removal.
  class ShareEntries
    def initialize(share)
      @share = share
    end

    def order = names.partition { |name| name != "rubies" }.flatten

    def remove
      emptied = prepare
      order.each { |name| Rubies.remove(File.join(share, name)) }
      Dir.rmdir(share) if emptied
      emptied
    end

    private

    attr_reader :share

    def prepare
      FlatShare.new(share, Releases.new(share)).migrate
      Dir.children(share).size == names.size
    end

    def names = Dir.children(share).select { |name| FlatShare::KEPT.include?(name) || name.match?(FlatShare::DOWNLOADS) }
  end
end
