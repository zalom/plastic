# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseInstallLockTest < Minitest::Test
  include ReleaseHelper

  def test_holding_the_lock_runs_the_step_and_returns_its_value
    assert_equal :done, InstallerRelease::InstallLock.hold(install_home) { :done }
  end

  def test_a_second_installer_stops_while_the_lock_is_held
    ran = false
    error = InstallerRelease::InstallLock.hold(install_home) do
      assert_raises(InstallerRelease::ActivationError) { InstallerRelease::InstallLock.hold(install_home) { ran = true } }
    end

    assert_equal [InstallerRelease::InstallLock::BUSY, false], [error.message, ran]
  end
end
