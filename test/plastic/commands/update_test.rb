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

  def test_names_the_installer_command_when_the_package_is_not_newer
    installed("99.0.0-alpha.1")
    before = tree_snapshot(@plastic_home)
    result = call("update", env: { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1") })

    assert_match(/install\.sh \| PLASTIC_CHANNEL=alpha sh/, result.out)
    assert_equal before, tree_snapshot(@plastic_home)
  end

  def test_activates_a_newer_release_on_the_installed_channel
    result = update_with_release("99.0.0-alpha.2")

    assert_equal [0, "99.0.0-alpha.2", "99.0.0-alpha.1"], [result.code, activation.active_version, activation.previous_version]
    assert_includes result.out, "claims no release trust"
    assert_match(/next:\s+plastic version/, result.out)
  end

  def test_an_activated_release_syncs_the_home
    result = update_with_release("99.0.0-alpha.2")

    assert_equal 0, result.code, result.err
    assert_equal ["install --reinstall"], launcher_calls
  end

  def test_takes_the_channel_the_documentation_names
    result = update_with_release("99.0.0-alpha.2", "--alpha")

    assert_equal [0, "99.0.0-alpha.2"], [result.code, activation.active_version], result.err
  end

  def test_refuses_more_than_one_channel
    result = update_with_release("99.0.0-alpha.2", "--alpha", "--beta")

    assert_equal 3, result.code
    assert_includes result.err, "choose one channel"
    assert_equal "99.0.0-alpha.1", activation.active_version
  end

  def test_names_the_chosen_channel_in_the_installer_command
    installed("99.0.0-alpha.1")
    result = call("update", "--beta", env: { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1") })

    assert_match(/install\.sh \| PLASTIC_CHANNEL=beta sh/, result.out)
  end

  def test_says_when_the_active_release_is_the_newest
    result = update_with_release("99.0.0-alpha.1")

    assert_equal 0, result.code, result.err
    assert_match(/newest release/, result.out)
    assert_nil activation.previous_version
  end

  def test_a_release_that_fails_its_checksum_changes_nothing
    directory = local_release("99.0.0-alpha.2")
    File.binwrite(File.join(directory, "plastic.tgz"), "corrupt")
    result = update_with_release("99.0.0-alpha.2", directory: directory)

    assert_equal 1, result.code
    assert_includes result.err, "archive checksum does not match"
    assert_equal ["99.0.0-alpha.1"], activation.releases.versions
  end

  def update_with_release(version, *options, directory: local_release(version))
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    call("update", *options, env: { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1"), "PLASTIC_LOCAL_RELEASE" => directory })
  end

  def test_refuses_to_update_a_home_that_has_no_installation
    result = call("update")

    assert_equal 3, result.code
    assert_includes result.err, "plastic install"
  end
end
