# frozen_string_literal: true

require_relative "installer_helper"

class RollbackCommandTest < Plastic::TestCase
  include InstallerHelper

  def test_switches_back_to_the_previous_release
    activated("2.0.2", "2.0.3")
    result = call("rollback")

    assert_equal 0, result.code, result.err
    assert_equal %w[2.0.2 2.0.3], [activation.active_version, activation.previous_version]
    assert_match(/next:\s+plastic install --reinstall/, result.out)
  end

  def test_switches_to_a_named_installed_release
    activated("2.0.1", "2.0.2", "2.0.3")
    result = call("rollback", "--version", "2.0.1")

    assert_equal 0, result.code, result.err
    assert_equal "2.0.1", activation.active_version
  end

  def test_a_dry_run_names_the_switch_and_changes_nothing
    activated("2.0.2", "2.0.3")
    before = tree_snapshot(share)
    result = call("rollback", "--dry-run")

    assert_equal 0, result.code, result.err
    assert_match(/active:\s+2\.0\.3/, result.out)
    assert_match(/to:\s+2\.0\.2/, result.out)
    assert_match(/releases:\s+2\.0\.2, 2\.0\.3/, result.out)
    assert_equal before, tree_snapshot(share)
    assert_equal %w[2.0.3 2.0.2], [activation.active_version, activation.previous_version]
  end

  def test_refuses_when_no_release_is_installed
    result = call("rollback")

    assert_equal 3, result.code
    assert_includes result.err, "install.sh"
  end

  def test_refuses_a_version_that_is_not_installed
    activated("2.0.2", "2.0.3")
    result = call("rollback", "--version", "1.0.0")

    assert_equal 3, result.code
    assert_includes result.err, "1.0.0 is not installed"
  end

  def test_refuses_when_there_is_no_previous_release
    activated("2.0.3")
    result = call("rollback")

    assert_equal 3, result.code
    assert_includes result.err, "no previous release"
  end
end
