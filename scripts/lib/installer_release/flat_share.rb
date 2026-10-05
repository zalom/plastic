# frozen_string_literal: true

require "fileutils"
require_relative "pointer"

module InstallerRelease
  # An install from before the releases layout kept one release's files
  # directly in the share directory. Moving them into releases/<version>
  # and pointing active at it makes that release the previous one after
  # the next activation. VERSION moves last, so a stopped move is finished
  # by the next installer.
  class FlatShare
    KEPT = %w[releases rubies active previous INSTALL.lock activation VERSION].freeze
    DOWNLOADS = /\Aplastic-(?:stage|download)-/

    def initialize(home, releases)
      @home = home
      @releases = releases
    end

    def migrate
      return unless flat?

      version = File.read(version_file).strip
      move_into(releases.path(version))
      Pointer.new(File.join(home, "active")).point_to(releases.pointer_target(version))
    end

    private

    attr_reader :home, :releases

    def move_into(destination)
      FileUtils.mkdir_p(destination)
      release_files.each { |name| File.rename(File.join(home, name), File.join(destination, name)) }
      File.rename(version_file, File.join(destination, "VERSION"))
    end

    def release_files = Dir.children(home).reject { |name| KEPT.include?(name) || name.match?(DOWNLOADS) }

    def version_file = File.join(home, "VERSION")

    def flat? = File.file?(version_file) && !File.symlink?(File.join(home, "active"))
  end
end
