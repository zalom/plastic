# frozen_string_literal: true

require_relative "support/install_sh_ruby_helper"

class InstallShRubyMacTest < Minitest::Test
  include InstallShRubyHelper

  def test_takes_the_apple_silicon_build_in_a_rosetta_shell
    on("Darwin", "x86_64")
    write_tool("sysctl", "#!/bin/sh\necho 1\n")
    install_with(ruby_archive)

    assert_equal ["https://ruby.test/arm64-darwin.tar.gz"], asked_for
  end

  def test_takes_the_homebrew_build_with_its_token_on_an_intel_mac
    on("Darwin", "x86_64")
    write_tool("sysctl", "#!/bin/sh\necho 0\n")
    _out, err, status = install_with(ruby_archive)

    assert_equal 0, status.exitstatus, err
    assert_equal ["#{ghcr_url} Authorization: Bearer QQ=="], asked_for
  end
end
