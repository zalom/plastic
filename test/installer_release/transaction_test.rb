# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseTransactionTest < Minitest::Test
  include ReleaseHelper

  def share = File.join(@root, "share")

  def releases = InstallerRelease::Releases.new(share)

  def journal = InstallerRelease::Journal.new(share, releases, -> { [] })

  def transaction = InstallerRelease::Transaction.new(share, releases, journal)

  def add_release(version)
    FileUtils.mkdir_p(releases.path(version))
    :added
  end

  def test_a_step_that_completes_returns_its_value_and_keeps_its_work
    assert_equal [:added, %w[2.0.3]], [transaction.run { add_release("2.0.3") }, releases.versions]
  end

  def test_a_completed_step_leaves_no_journal
    transaction.run { add_release("2.0.3") }

    refute_path_exists File.join(share, "activation")
  end

  def test_a_failed_step_is_undone_and_raised_as_an_activation_error
    error = assert_raises(InstallerRelease::ActivationError) do
      transaction.run { add_release("2.0.3") && raise("disk full") }
    end

    assert_equal ["disk full", []], [error.message, releases.versions]
  end

  def test_a_flat_share_moves_into_the_releases_layout_first
    FileUtils.mkdir_p(share)
    File.write(File.join(share, "VERSION"), "2.0.2\n")

    assert_equal %w[2.0.2], transaction.run { releases.versions }
  end

  def test_a_step_while_another_installer_holds_the_lock_does_not_run
    ran = false

    InstallerRelease::InstallLock.hold(share) do
      assert_raises(InstallerRelease::ActivationError) { transaction.run { ran = true } }
    end

    refute ran
  end
end
