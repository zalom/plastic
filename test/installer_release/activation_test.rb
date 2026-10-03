# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseActivationTest < Minitest::Test
  include ReleaseHelper

  def test_keeps_a_previous_version_and_rolls_back
    installer = activation_with("2.0.2", "2.0.3")

    assert_equal %w[2.0.3 2.0.2], versions(installer)
    assert_equal "2.0.2", installer.rollback
    assert_equal "old\n", File.read(File.join(installer.active_path, "bin", "plastic"))
  end

  def test_refuses_a_rollback_without_a_previous_release
    installer = activation_with("2.0.2")

    error = assert_raises(InstallerRelease::ActivationError) { installer.rollback }
    assert_equal "no previous release is available", error.message
  end

  def test_a_failure_before_the_switch_leaves_the_old_active_usable
    installer = activation_with("2.0.2")
    candidate = staged_candidate("2.0.3")

    assert_raises(InstallerRelease::ActivationError) do
      installer.activate(candidate, version: "2.0.3", before_switch: -> { raise "injected failure" })
    end
    assert_equal "old\n", File.read(File.join(installer.active_path, "bin", "plastic"))
    assert_path_exists candidate
  end

  def test_a_failed_active_pointer_switch_keeps_the_previous_pointer
    installer, candidate = failed_switch

    assert_equal %w[2.0.2 2.0.1], versions(installer)
    assert_path_exists candidate
  end

  def test_a_failed_active_pointer_switch_leaves_the_candidate_retryable
    installer, candidate = failed_switch
    installer.fail_active = false
    installer.activate(candidate, version: "2.0.3")

    assert_equal %w[2.0.3 2.0.2], versions(installer)
  end

  def test_a_failed_first_activation_leaves_no_pointers
    installer = failing_pointer_activation
    installer.fail_active = true

    assert_raises(InstallerRelease::ActivationError) { installer.activate(staged_candidate("2.0.3"), version: "2.0.3") }
    assert_equal [nil, nil], versions(installer)
    refute_path_exists installer.active_path
  end

  def test_refuses_a_version_that_is_already_installed
    installer = activation_with("2.0.3")

    error = assert_raises(InstallerRelease::ActivationError) do
      installer.activate(staged_candidate("2.0.3"), version: "2.0.3")
    end
    assert_equal "release version already exists", error.message
  end

  def test_refuses_a_candidate_on_another_filesystem
    elsewhere = Class.new(InstallerRelease::Releases) { def same_filesystem?(_candidate) = false }.new(install_home)
    installer = InstallerRelease::Activation.new(home: install_home, releases: elsewhere)

    error = assert_raises(InstallerRelease::ActivationError) { installer.activate(staged_candidate("2.0.3"), version: "2.0.3") }
    assert_equal "candidate is not on the installation filesystem", error.message
  end

  def test_switches_to_any_installed_release
    installer = activation_with("2.0.1", "2.0.2", "2.0.3")

    assert_equal "2.0.1", installer.switch("2.0.1")
    assert_equal %w[2.0.1 2.0.3], versions(installer)
  end

  def test_lists_the_installed_releases
    installer = activation_with("2.0.1", "2.0.2", "2.0.3")

    assert_equal %w[2.0.1 2.0.2 2.0.3], installer.releases.versions
    assert installer.releases.installed?("2.0.2")
  end

  def test_refuses_to_switch_to_a_release_that_is_not_installed
    installer = activation_with("2.0.2")

    error = assert_raises(InstallerRelease::ActivationError) { installer.switch("1.0.0") }
    assert_equal "1.0.0 is not installed", error.message
  end

  def test_a_home_with_no_releases_lists_none
    installer = InstallerRelease::Activation.new(home: install_home)

    assert_empty installer.releases.versions
    refute installer.releases.installed?("2.0.3")
  end

  def test_lists_the_installed_releases_in_version_order
    installer = activation_with("2.0.10", "2.0.9", "2.0.10-alpha.1")

    assert_equal %w[2.0.9 2.0.10-alpha.1 2.0.10], installer.releases.versions
  end

  private

  def failed_switch
    installer = activation_with("2.0.1", "2.0.2", activation: failing_pointer_activation)
    candidate = staged_candidate("2.0.3")
    installer.fail_active = true
    assert_raises(InstallerRelease::ActivationError) { installer.activate(candidate, version: "2.0.3") }
    [installer, candidate]
  end

  def failing_pointer_activation
    Class.new(InstallerRelease::Activation) do
      attr_accessor :fail_active

      private

      def replace_pointer(path, version)
        raise "injected active pointer failure" if fail_active && path == active_path

        super
      end
    end.new(home: install_home)
  end
end
