# frozen_string_literal: true

require "rubygems/package"
require "zlib"
require_relative "support/install_sh_helper"

class InstallShLocalTest < Minitest::Test
  include InstallShHelper

  def test_installs_a_local_release_and_links_the_launcher
    _out, err, status = install_local("2.0.3")

    assert_equal 0, status.exitstatus, err
    assert_equal "2.0.3\n", run_launcher
    assert_equal "2.0.3", InstallerRelease::Activation.new(home: share).active_version
  end

  def test_a_local_release_claims_no_trust_and_names_the_next_command
    out, = install_local("2.0.3")

    assert_includes out, "claims no release trust"
    assert_includes out, "next: plastic install"
  end

  def test_a_second_install_of_the_same_release_succeeds
    install_local("2.0.3")
    _out, err, status = install_local("2.0.3")

    assert_equal 0, status.exitstatus, err
    assert_equal "2.0.3\n", run_launcher
  end

  def test_prints_a_path_hint_and_edits_no_profile
    out, = install_local("2.0.3")

    assert_includes out, "is not on your PATH"
    assert_empty Dir.children(@home) - [".local"]
  end

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

  def test_leaves_a_launcher_the_user_wrote_alone
    FileUtils.mkdir_p(File.dirname(launcher))
    File.write(launcher, "#!/bin/sh\necho mine\n")
    out, err, status = install_local("2.0.3")

    assert_equal 0, status.exitstatus, err
    assert_equal "#!/bin/sh\necho mine\n", File.read(launcher)
    assert_includes out, "is not Plastic's launcher"
  end

  def test_rejects_an_override_url
    _out, err, status = install(PLASTIC_ARCHIVE_URL: "https://example.test/plastic.tgz")

    assert_equal 1, status.exitstatus
    assert_includes err, "PLASTIC_LOCAL_RELEASE"
  end

  def test_a_dry_run_reads_the_release_and_changes_nothing
    out, err, status = install_local("2.0.3", "--dry-run")

    assert_equal 0, status.exitstatus, err
    assert_includes out, "would install Plastic 2.0.3"
    refute_path_exists File.join(@home, ".local")
  end

  def test_refuses_an_unknown_channel
    _out, err, status = install(PLASTIC_CHANNEL: "nightly")

    assert_equal 1, status.exitstatus
    assert_includes err, "stable, beta or alpha"
  end
end
