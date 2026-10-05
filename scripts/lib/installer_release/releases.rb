# frozen_string_literal: true

require "rubygems/version"

module InstallerRelease
  # The releases/ directory of an install home: one directory per installed version.
  class Releases
    attr_reader :root

    def initialize(home)
      @root = File.join(home, "releases")
    end

    def path(version) = File.join(root, version)

    def installed?(version) = File.directory?(path(version))

    def versions = File.directory?(root) ? Dir.children(root).sort_by { |version| Gem::Version.new(version) } : []

    def same_filesystem?(candidate) = File.stat(candidate).dev == File.stat(root).dev

    def pointer_target(version) = File.join(File.basename(root), version)
  end
end
