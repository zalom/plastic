# frozen_string_literal: true

require_relative "support/install_sh_ruby_helper"

class InstallShRubyTest < Minitest::Test
  include InstallShRubyHelper

  def test_installs_the_pinned_ruby_and_a_launcher_that_needs_no_path
    _out, err, status = install_with(ruby_archive)

    assert_equal 0, status.exitstatus, err
    assert_equal ["#{@sha}\n", "2.0.3\n"], [File.read(File.join(ruby_folder, ".plastic-ruby")), launch_with_empty_path]
    assert_includes File.read(File.join(share, "active", "bin", "plastic")), File.join(ruby_folder, "bin", "ruby")
  end

  def test_a_second_install_reuses_the_ruby
    install_with(ruby_archive)
    _out, err, status = install_with(ruby_archive)

    assert_equal 0, status.exitstatus, err
    assert_equal 1, asked_for.size
  end
end
