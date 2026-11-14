# frozen_string_literal: true

require_relative "installer_helper"

class RollbackCommandTest < Plastic::TestCase
  include InstallerHelper

  def test_names_the_switch_to_the_previous_release_and_changes_nothing
    activated("2.0.2", "2.0.3")
    before = tree_snapshot(share)
    result = call("rollback")

    assert_equal 0, result.code, result.err
    assert_equal [before, %w[2.0.3 2.0.2]], [tree_snapshot(share), [activation.active_version, activation.previous_version]]
    assert_equal [], launcher_calls
    assert_equal switch_line("2.0.2"), result.out[/^next:\s+(.*)$/, 1]
  end

  def test_names_the_switch_to_a_named_installed_release
    activated("2.0.1", "2.0.2", "2.0.3")
    result = call("rollback", "--version", "2.0.1")

    assert_equal [0, switch_line("2.0.1"), "2.0.3"], [result.code, result.out[/^next:\s+(.*)$/, 1], activation.active_version], result.err
  end

  def test_a_dry_run_names_the_switch_and_changes_nothing
    activated("2.0.2", "2.0.3")
    before = tree_snapshot(share)
    result = call("rollback", "--dry-run")

    assert_match(/active:\s+2\.0\.3\n.*to:\s+2\.0\.2\n.*releases:\s+2\.0\.2, 2\.0\.3/m, result.out)
    assert_equal [0, before], [result.code, tree_snapshot(share)]
    assert_equal %w[2.0.3 2.0.2], [activation.active_version, activation.previous_version]
  end

  def switch_line(version)
    [RbConfig.ruby, "--disable-gems", "-rrbconfig", File.join(share, "releases", "2.0.3", "scripts", "install-release"), "--switch", version,
     "--home", share, "--bin", File.join(@home, ".local", "bin"), "--plastic-home", @plastic_home, "--user-home", @home].join(" ")
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
