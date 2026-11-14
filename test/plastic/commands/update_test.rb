# frozen_string_literal: true

require_relative "installer_helper"

class UpdateCommandTest < Plastic::TestCase
  include InstallerHelper

  def test_a_dry_run_names_both_versions_and_changes_nothing
    installed("0.0.1")
    before = tree_snapshot(@plastic_home)
    result = call("update", "--dry-run")

    assert_match(/from:\s+0\.0\.1/, result.out)
    assert_match(/to:\s+#{Regexp.escape(package_version)}/, result.out)
    assert_equal before, tree_snapshot(@plastic_home)
  end

  def test_syncs_a_newer_package_into_the_home
    installed("0.0.1")
    result = call("update")

    assert_equal 0, result.code, result.err
    assert_equal "#{package_version}\n", File.read(File.join(@plastic_home, "VERSION"))
  end

  def test_the_old_channel_switches_are_gone
    installed("99.0.0-alpha.1")

    %w[--stable --beta --alpha].each { |switch| assert_equal 2, call("update", switch).code, switch }
  end

  def test_an_unknown_channel_name_is_a_usage_error
    result = update_with_release("99.0.0-alpha.2", "--channel", "nightly")

    assert_equal 2, result.code
    assert_includes result.err, "stable, beta or alpha"
    assert_equal "99.0.0-alpha.1", activation.active_version
  end

  def test_an_empty_channel_name_is_a_usage_error
    result = update_with_release("99.0.0-alpha.2", "--channel", "")

    assert_equal 2, result.code
    assert_includes result.err, "stable, beta or alpha"
  end

  def test_says_when_the_active_release_is_the_newest
    result = update_with_release("99.0.0-alpha.1")

    assert_equal 0, result.code, result.err
    assert_match(/newest release/, result.out)
    assert_nil activation.previous_version
  end

  def test_downloads_the_three_files_and_names_the_install_command
    result = update_with_release("99.0.0-alpha.2")

    assert_equal [0, %w[plastic.manifest.json plastic.tgz plastic.tgz.sha256], install_line("99.0.0-alpha.2")],
      [result.code, Dir.children(download).sort, result.out[/^next:\s+(.*)$/, 1]], result.err
  end

  def test_downloading_leaves_the_active_release_alone
    update_with_release("99.0.0-alpha.2")

    assert_equal ["99.0.0-alpha.1", nil], [activation.active_version, activation.previous_version]
  end

  def test_the_channel_the_documentation_names_is_accepted
    result = update_with_release("99.0.0-alpha.2", "--channel", "alpha")

    assert_equal [0, install_line("99.0.0-alpha.2")], [result.code, result.out[/^next:\s+(.*)$/, 1]], result.err
  end

  def test_empties_the_download_folder_before_each_run
    FileUtils.mkdir_p(download)
    File.write(File.join(download, "left-over"), "x")
    update_with_release("99.0.0-alpha.2")

    refute_path_exists File.join(download, "left-over")
  end

  def test_a_release_that_fails_its_checksum_empties_the_download_folder_and_exits_1
    directory = local_release("99.0.0-alpha.2")
    File.binwrite(File.join(directory, "plastic.tgz"), "corrupt")
    result = update_with_release("99.0.0-alpha.2", directory: directory)

    assert_equal 1, result.code
    assert_includes result.err, "archive checksum does not match"
    assert_equal [[], ["99.0.0-alpha.1"]], [Dir.children(download), activation.releases.versions]
  end

  def test_with_no_active_release_it_names_install_sh_and_no_channel_variable
    installed("99.0.0-alpha.1")
    result = call("update", env: { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1") })

    assert_includes result.out, "install.sh"
    refute_includes result.out, "PLASTIC_CHANNEL"
  end

  def download = File.join(share, "download")

  def install_line(version)
    [RbConfig.ruby, "--disable-gems", "-rrbconfig", File.join(share, "releases", "99.0.0-alpha.1", "scripts", "install-release"),
      "--directory", download, "--version", version, "--home", share, "--bin", File.join(@home, ".local", "bin"),
      "--plastic-home", @plastic_home, "--user-home", @home].join(" ")
  end

  def update_with_release(version, *options, directory: local_release(version))
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    call("update", *options, env: { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1"), "PLASTIC_LOCAL_RELEASE" => directory })
  end
end
