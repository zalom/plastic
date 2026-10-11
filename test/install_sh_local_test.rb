# frozen_string_literal: true

require_relative "support/install_sh_helper"

class InstallShLocalTest < Minitest::Test
  include InstallShHelper

  def test_installs_a_local_release_and_links_the_launcher
    _out, err, status = install_local("2.0.3")

    assert_equal 0, status.exitstatus, err
    assert_equal "2.0.3\n", run_launcher
    assert_equal "2.0.3", InstallerRelease::Activation.new(home: share).active_version
  end

  def test_a_second_install_of_the_same_release_succeeds
    install_local("2.0.3")
    _out, err, status = install_local("2.0.3")

    assert_equal 0, status.exitstatus, err
    assert_equal "2.0.3\n", run_launcher
  end

  def test_leaves_a_launcher_the_user_wrote_alone
    FileUtils.mkdir_p(File.dirname(launcher))
    File.write(launcher, "#!/bin/sh\necho mine\n")
    out, err, status = install_local("2.0.3")

    assert_equal 0, status.exitstatus, err
    assert_equal "#!/bin/sh\necho mine\n", File.read(launcher)
    assert_includes out, "is not Plastic's launcher"
  end

  def test_a_dry_run_reads_the_release_and_changes_nothing
    out, err, status = install_local("2.0.3", "--dry-run")

    assert_equal 0, status.exitstatus, err
    assert_includes out, "would install Plastic 2.0.3"
    refute_path_exists File.join(@home, ".local")
  end
end
