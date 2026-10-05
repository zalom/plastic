# frozen_string_literal: true

require_relative "support/install_sh_ruby_helper"

class InstallShRubyArchiveTest < Minitest::Test
  include InstallShRubyHelper

  def test_a_wrong_size_leaves_no_ruby
    _out, err, status = install_with(ruby_archive, size: File.size(ruby_archive) + 1)

    assert_equal 1, status.exitstatus
    assert_includes err, "not the pinned"
    refute_path_exists File.join(share, "rubies")
  end

  def test_a_wrong_fingerprint_leaves_no_ruby
    _out, err, status = install_with(ruby_archive, sha: "0" * 64)

    assert_equal 1, status.exitstatus
    assert_includes err, "does not match its pinned SHA-256"
    refute_path_exists File.join(share, "rubies")
  end

  def test_an_archive_with_a_link_leaves_no_ruby
    _out, err, status = install_with(archive_of("linked") { |bin| File.symlink("/bin/sh", File.join(bin, "ruby")) })

    assert_equal 1, status.exitstatus
    assert_includes err, "the Ruby archive holds an unsafe entry"
    refute_path_exists File.join(share, "rubies")
  end

  def test_a_ruby_that_does_not_start_leaves_no_ruby_folder
    _out, err, status = install_with(archive_of("broken") { |bin| executable(File.join(bin, "ruby"), "#!/bin/sh\necho broken\n") })

    assert_equal 1, status.exitstatus
    assert_includes err, "the downloaded Ruby does not start: broken"
    assert_empty Dir.children(File.join(share, "rubies"))
  end
end
