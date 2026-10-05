# frozen_string_literal: true

require "rbconfig"

module InstallerRelease
  # One Ruby a release runs on, by the full path of its ruby program.
  Ruby = Data.define(:path) do
    def bundle = File.join(File.dirname(path), "bundle")
  end

  # The platform name install.sh pins a Ruby for, from the running Ruby's
  # build, or nil for a platform without a build.
  module Platform
    NAMES = { %w[darwin arm64] => "arm64-darwin", %w[darwin x86_64] => "x86_64-darwin", %w[linux x86_64] => "x86_64-linux",
              %w[linux aarch64] => "aarch64-linux" }.freeze

    def self.local(config = RbConfig::CONFIG) = NAMES[[config.fetch("host_os")[/darwin|linux/], config.fetch("host_cpu")]]
  end

  # The Ruby a release runs on: the developer's PLASTIC_RUBY, else the build
  # the release manifest pins for this platform, else the running Ruby for a
  # release from before the pins.
  class RubyChoice
    def initialize(home:, override: "", platform: Platform.local, rubies: Rubies.new(home))
      @override = override.to_s
      @platform = platform
      @rubies = rubies
    end

    def call(manifest)
      return Ruby.new(override) unless override.empty?

      build = manifest.dig("ruby", "builds", platform.to_s)
      build ? rubies.provide(build) : Ruby.new(RbConfig.ruby)
    end

    private

    attr_reader :override, :platform, :rubies
  end
end
