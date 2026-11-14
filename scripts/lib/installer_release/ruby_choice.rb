# frozen_string_literal: true

require "rbconfig"

module InstallerRelease
  # One Ruby a release runs on, by the full path of its ruby program.
  Ruby = Data.define(:path) do
    def bundle = File.join(File.dirname(path), "bundle")
  end

  # The Ruby a release runs on: the developer's PLASTIC_RUBY, else the Ruby
  # that is running the installer.
  class RubyChoice
    def initialize(override: "")
      @override = override.to_s
    end

    def call(_manifest) = Ruby.new(override.empty? ? RbConfig.ruby : override)

    private

    attr_reader :override
  end
end
