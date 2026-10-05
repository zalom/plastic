# frozen_string_literal: true

require_relative "support/install_sh_ruby_helper"

class InstallShRubyPlatformTest < Minitest::Test
  include InstallShRubyHelper

  def test_takes_the_linux_build_on_linux
    install_with(ruby_archive)

    assert_equal ["https://ruby.test/x86_64-linux.tar.gz"], asked_for
  end

  def test_stops_on_a_musl_system
    write_tool("ldd", "#!/bin/sh\necho 'musl libc (x86_64)' >&2\nexit 1\n")
    _out, err, status = install_with(ruby_archive)

    assert_equal 1, status.exitstatus
    assert_includes err, "Alpine and other musl systems are not supported: Plastic's Ruby needs glibc 2.29 or later."
    refute_path_exists share
  end

  def test_stops_on_a_platform_without_a_build
    on("FreeBSD", "amd64")
    _out, err, status = install_with(ruby_archive)

    assert_equal 1, status.exitstatus
    assert_includes err, "no Ruby build exists for FreeBSD amd64"
    assert_includes err, "WSL"
  end

  def test_a_dry_run_writes_nothing_under_the_share
    out, err, status = install_with(ruby_archive, "--dry-run")

    assert_equal 0, status.exitstatus, err
    assert_includes out, "would run it with"
    refute_path_exists share
  end
end
