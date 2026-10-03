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

  def test_a_second_installer_fails_cleanly_while_the_lock_is_held
    installer = activation_with("2.0.2")
    candidate = staged_candidate("2.0.3")
    error = File.open(File.join(install_home, "INSTALL.lock"), "a") do |lock|
      lock.flock(File::LOCK_EX)
      assert_raises(InstallerRelease::ActivationError) { installer.activate(candidate, version: "2.0.3") }
    end

    assert_match(/another Plastic installer is running/, error.message)
    assert_equal [%w[2.0.2], "2.0.2"], [installer.releases.versions, installer.active_version]
    assert_path_exists candidate
  end

  def test_a_failed_home_sync_restores_the_pointers_and_the_home
    installer, sync = synced_with("2.0.2")
    sync.failure = RuntimeError.new("injected sync failure")
    candidate = staged_candidate("2.0.3")

    assert_raises(InstallerRelease::ActivationError) { installer.activate(candidate, version: "2.0.3") }
    assert_equal [["2.0.2", nil], %w[2.0.2], "original\n"], [versions(installer), installer.releases.versions, home_file]
    refute_path_exists File.join(@root, "added.md")
    assert_equal %w[INSTALL.lock active releases], Dir.children(install_home).sort
    assert_path_exists candidate
  end

  def test_a_failed_home_sync_can_be_run_again
    installer, sync = synced_with("2.0.2")
    sync.failure = RuntimeError.new("injected sync failure")
    candidate = staged_candidate("2.0.3")
    assert_raises(InstallerRelease::ActivationError) { installer.activate(candidate, version: "2.0.3") }
    sync.failure = nil
    installer.activate(candidate, version: "2.0.3")

    assert_equal [%w[2.0.3 2.0.2], "changed\n"], [versions(installer), home_file]
  end

  def test_an_interrupted_activation_recovers_the_previous_state
    installer, sync = synced_with("2.0.2", "2.0.3")
    sync.failure = Interrupt.new
    assert_raises(Interrupt) { installer.activate(staged_candidate("2.0.4"), version: "2.0.4") }
    installer.recover

    assert_equal [%w[2.0.3 2.0.2], %w[2.0.2 2.0.3], "original\n"], [versions(installer), installer.releases.versions, home_file]
    refute_path_exists File.join(@root, "added.md")
  end

  def test_a_rollback_syncs_the_home_of_the_release_it_switches_to
    installer, sync = synced_with("2.0.2", "2.0.3")
    installer.rollback

    assert_equal %w[2.0.2 2.0.3 2.0.2], sync.seen
  end

  def test_a_failed_rollback_sync_keeps_the_active_release
    installer, sync = synced_with("2.0.2", "2.0.3")
    sync.failure = RuntimeError.new("injected sync failure")

    assert_raises(InstallerRelease::ActivationError) { installer.rollback }
    assert_equal [%w[2.0.3 2.0.2], "original\n"], [versions(installer), home_file]
  end

  def test_moves_a_flat_share_into_the_releases_layout
    write_package(install_home, "2.0.1", "flat\n")
    installer = activation_with("2.0.3")

    assert_equal [%w[2.0.3 2.0.1], %w[2.0.1 2.0.3]], [versions(installer), installer.releases.versions]
    assert_equal %w[INSTALL.lock active previous releases], Dir.children(install_home).sort
    assert_equal "flat\n", File.read(File.join(installer.previous_path, "bin", "plastic"))
  end

  private

  def synced_with(*installed)
    sync = SyncDouble.new(@root, install_home)
    installer = activation_with(*installed, activation: InstallerRelease::Activation.new(home: install_home, sync: sync))
    File.write(sync.paths.first, "original\n")
    FileUtils.rm_f(sync.paths.last)
    [installer, sync]
  end

  def home_file = File.read(File.join(@root, "PLASTIC.md"))

  def activation_with(*installed, activation: InstallerRelease::Activation.new(home: install_home))
    installed.each { |version| activation.activate(staged_candidate(version), version: version) }
    activation
  end

  def failed_switch
    installer = activation_with("2.0.1", "2.0.2", activation: failing_pointer_activation)
    candidate = staged_candidate("2.0.3")
    installer.fail_active = true
    assert_raises(InstallerRelease::ActivationError) { installer.activate(candidate, version: "2.0.3") }
    [installer, candidate]
  end

  def versions(installer) = [installer.active_version, installer.previous_version]

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
