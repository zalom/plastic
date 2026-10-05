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
    installer = Class.new(InstallerRelease::Activation) do
      private

      def same_filesystem?(_candidate) = false
    end.new(home: install_home)

    error = assert_raises(InstallerRelease::ActivationError) { installer.activate(staged_candidate("2.0.3"), version: "2.0.3") }
    assert_equal "candidate is not on the installation filesystem", error.message
  end

  private

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
