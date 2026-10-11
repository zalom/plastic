# frozen_string_literal: true

require "rubygems/package"
require "zlib"
require_relative "support/install_sh_helper"

class InstallShRefusalTest < Minitest::Test
  include InstallShHelper

  def test_a_failed_checksum_leaves_the_installed_release_untouched
    install_local("2.0.2")
    File.binwrite(File.join(release("2.0.3"), "plastic.tgz"), "corrupt")
    _out, err, status = install_local("2.0.3")

    assert_includes err, "checksum"
    assert_equal [1, "2.0.2\n", ["2.0.2"]], [status.exitstatus, run_launcher, InstallerRelease::Releases.new(share).versions]
  end

  def test_refuses_a_release_other_than_the_requested_version
    _out, err, status = install_local("2.0.3", PLASTIC_VERSION: "2.0.4")

    assert_equal 1, status.exitstatus
    assert_includes err, "v2.0.4"
    refute_path_exists share
  end

  def test_refuses_an_archive_with_a_link_before_extracting_it
    directory = release("2.0.3-link") { |package| File.symlink("/etc", File.join(package, "scripts", "lib", "installer_release", "escape")) }
    _out, err, status = install(PLASTIC_LOCAL_RELEASE: directory)

    assert_equal 1, status.exitstatus
    assert_includes err, "plastic.tgz holds an unsafe entry"
    refute_path_exists share
  end

  def test_refuses_an_archive_with_a_parent_path_before_extracting_it
    directory = File.join(@dir, "releases", "v2.0.3-parent")
    FileUtils.mkdir_p(directory)
    Zlib::GzipWriter.open(File.join(directory, "plastic.tgz")) do |gzip|
      Gem::Package::TarWriter.new(gzip) { |tar| tar.add_file_simple("package/../../escape", 0o644, 1) { |io| io.write("x") } }
    end
    _out, err, status = install(PLASTIC_LOCAL_RELEASE: publish(directory, "2.0.3"))

    assert_equal 1, status.exitstatus
    assert_includes err, "plastic.tgz holds an unsafe entry"
    refute_path_exists File.join(@dir, "escape")
  end

  def test_rejects_an_override_url
    _out, err, status = install(PLASTIC_ARCHIVE_URL: "https://example.test/plastic.tgz")

    assert_equal 1, status.exitstatus
    assert_includes err, "PLASTIC_LOCAL_RELEASE"
  end

  def test_refuses_an_unknown_channel
    _out, err, status = install(PLASTIC_CHANNEL: "nightly")

    assert_equal 1, status.exitstatus
    assert_includes err, "stable, beta or alpha"
  end
end
