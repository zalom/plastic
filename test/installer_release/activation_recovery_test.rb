# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseActivationRecoveryTest < Minitest::Test
  include ReleaseHelper

  def test_a_second_installer_fails_cleanly_while_the_lock_is_held
    installer = activation_with("2.0.2")
    candidate = staged_candidate("2.0.3")
    error = File.open(File.join(install_home, "INSTALL.lock"), "a") do |lock|
      lock.flock(File::LOCK_EX)
      assert_raises(InstallerRelease::ActivationError) { installer.activate(candidate, version: "2.0.3") }
    end

    assert_match(/another Plastic installer is running/, error.message)
    assert_equal [%w[2.0.2], "2.0.2", true], [installer.releases.versions, installer.active_version, File.directory?(candidate)]
  end

  def test_a_failed_home_sync_restores_the_pointers_and_the_home
    installer, sync = synced_with("2.0.2")
    sync.failure = RuntimeError.new("injected sync failure")
    candidate = staged_candidate("2.0.3")

    assert_raises(InstallerRelease::ActivationError) { installer.activate(candidate, version: "2.0.3") }
    assert_equal [["2.0.2", nil], %w[2.0.2], "original\n", false, %w[INSTALL.lock active releases], true],
      [*state(installer), File.directory?(candidate)]
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

    assert_equal [%w[2.0.3 2.0.2], %w[2.0.2 2.0.3], "original\n", false], state(installer).first(4)
  end

  def test_a_journal_stopped_before_its_state_is_discarded
    installer, = synced_with("2.0.2", "2.0.3")
    FileUtils.mkdir_p(File.join(install_home, "activation", "home"))
    installer.recover

    assert_equal [%w[2.0.3 2.0.2], %w[2.0.2 2.0.3], "original\n", false, %w[INSTALL.lock active previous releases]], state(installer)
  end

  def test_a_rollback_syncs_the_home_of_the_release_it_switches_to
    installer, sync = synced_with("2.0.2", "2.0.3")
    installer.switch(installer.previous_version)

    assert_equal %w[2.0.2 2.0.3 2.0.2], sync.seen
  end

  def test_a_failed_rollback_sync_keeps_the_active_release
    installer, sync = synced_with("2.0.2", "2.0.3")
    sync.failure = RuntimeError.new("injected sync failure")

    assert_raises(InstallerRelease::ActivationError) { installer.switch(installer.previous_version) }
    assert_equal [%w[2.0.3 2.0.2], "original\n"], [versions(installer), home_file]
  end

  def test_moves_a_flat_share_into_the_releases_layout
    write_package(install_home, "2.0.1", flat = fake_launcher("2.0.1"))
    installer = activation_with("2.0.3")

    assert_equal [%w[2.0.3 2.0.1], %w[2.0.1 2.0.3]], [versions(installer), installer.releases.versions]
    assert_equal %w[INSTALL.lock active previous releases], Dir.children(install_home).sort
    assert_equal flat, File.read(File.join(installer.previous_path, "bin", "plastic"))
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

  def state(installer)
    added = File.exist?(File.join(@root, "added.md"))
    [versions(installer), installer.releases.versions, home_file, added, Dir.children(install_home).sort]
  end
end
