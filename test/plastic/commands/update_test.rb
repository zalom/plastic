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

    assert_match(/PLASTIC_CHANNEL=alpha sh install\.sh/, result.out)
    assert_equal before, tree_snapshot(@plastic_home)
  end

  def test_refuses_to_update_a_home_that_has_no_installation
    result = call("update")

    assert_equal 3, result.code
    assert_includes result.err, "plastic install"
  end
end
