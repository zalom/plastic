# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseRubyPinsTest < Minitest::Test
  include ReleaseHelper

  def test_install_sh_pins_a_ruby_for_each_supported_platform
    assert_equal %w[aarch64-linux arm64-darwin x86_64-darwin x86_64-linux], pins.keys.sort
  end

  def test_every_pin_names_ruby_4_0_7_by_size_and_fingerprint
    pins.each_value do |pin|
      assert_equal "4.0.7", pin.fetch("version")
      assert_kind_of Integer, pin.fetch("size")
      assert_match(/\A\h{64}\z/, pin.fetch("sha256"))
    end
  end

  def test_jdx_serves_apple_silicon_and_both_linux_builds
    %w[arm64-darwin x86_64-linux aarch64-linux].each do |platform|
      assert pins.dig(platform, "url").start_with?("https://github.com/jdx/ruby/releases/download/4.0.7-2/"), platform
    end
  end

  def test_homebrew_serves_intel_macs_by_the_pinned_fingerprint
    intel = pins.fetch("x86_64-darwin")

    assert_equal "https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:#{intel.fetch("sha256")}", intel.fetch("url")
  end

  def test_reads_a_table_from_any_script
    table = InstallerRelease::RubyPins.read("x=1\nruby_pins='\narm64-darwin k 4.0.7 12 #{"a" * 64} r https://example.test/r.tgz\n'\n")

    assert_equal({ "arm64-darwin" => { "key" => "k", "version" => "4.0.7", "size" => 12, "sha256" => "a" * 64, "root" => "r",
                                       "url" => "https://example.test/r.tgz" } }, table)
  end

  def test_refuses_a_script_without_the_table
    error = assert_raises(InstallerRelease::VerificationError) { InstallerRelease::RubyPins.read("echo hi\n") }

    assert_equal "install.sh has no ruby_pins table", error.message
  end

  private

  def pins = InstallerRelease::RubyPins.read
end
