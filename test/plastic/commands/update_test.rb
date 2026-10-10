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
    result = update_with_release("99.0.0-alpha.2", "--channel", "alpha")

    assert_equal [0, "99.0.0-alpha.2"], [result.code, activation.active_version], result.err
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

  def test_names_the_chosen_channel_in_the_installer_command
    installed("99.0.0-alpha.1")
    result = call("update", "--channel", "beta", env: { "PLASTIC_PACKAGE_ROOT" => fake_package("99.0.0-alpha.1") })

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

  def test_prints_the_release_notice_before_the_home_sync_output
    lines = update_with_release("99.0.0-alpha.2").out.lines(chomp: true)
    notice = lines.index { |line| line.include?("claims no release trust") }

    assert_operator notice, :<, lines.index("99.0.0-alpha.2").to_i
  end

  def test_a_settings_file_that_is_not_json_names_the_file_and_changes_nothing
    settings = File.join(claude_folder, "settings.json")
    File.write(settings, "{ not json")
    result = update_with_release("99.0.0-alpha.2")

    assert_equal 1, result.code
    assert_includes result.err, "#{settings} is not valid JSON; nothing was changed"
    assert_equal ["99.0.0-alpha.1", "{ not json"], [activation.active_version, File.read(settings)]
  end
end
