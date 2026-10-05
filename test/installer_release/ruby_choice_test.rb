# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseRubyChoiceTest < Minitest::Test
  include ReleaseHelper

  BUILD = { "key" => "4.0.7-jdx-2", "sha256" => "a" * 64 }.freeze

  # Stands in for Rubies: hands back a pinned Ruby and records each build.
  class RubiesDouble
    attr_reader :provided

    def initialize
      @provided = []
    end

    def provide(build)
      @provided << build
      InstallerRelease::Ruby.new("/rubies/#{build.fetch("key")}/bin/ruby")
    end
  end

  def test_names_the_platform_of_each_supported_build
    names = [%w[darwin24 arm64], %w[darwin23 x86_64], %w[linux-gnu x86_64], %w[linux aarch64], %w[freebsd14 amd64]]
      .map { |os, cpu| InstallerRelease::Platform.local("host_os" => os, "host_cpu" => cpu) }

    assert_equal ["arm64-darwin", "x86_64-darwin", "x86_64-linux", "aarch64-linux", nil], names
  end

  def test_the_bundle_program_sits_beside_the_ruby
    assert_equal "/r/bin/bundle", InstallerRelease::Ruby.new("/r/bin/ruby").bundle
  end

  def test_takes_the_developer_ruby_first
    assert_equal "/dev/ruby", choice(override: "/dev/ruby").call(pinning).path
    assert_empty rubies.provided
  end

  def test_takes_the_build_the_manifest_pins_for_the_platform
    assert_equal "/rubies/4.0.7-jdx-2/bin/ruby", choice.call(pinning).path
  end

  def test_keeps_the_running_ruby_for_a_release_without_pins
    assert_equal RbConfig.ruby, choice.call({ "ruby" => { "requirement" => ">= 4.0.0" } }).path
  end

  private

  def rubies = (@rubies ||= RubiesDouble.new)

  def choice(override: "") = InstallerRelease::RubyChoice.new(home: @root, override: override, platform: "arm64-darwin", rubies: rubies)

  def pinning = { "ruby" => { "builds" => { "arm64-darwin" => BUILD } } }
end
