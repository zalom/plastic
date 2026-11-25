# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseJournalTest < Minitest::Test
  include ReleaseHelper

  def share = File.join(@root, "share")

  def releases = InstallerRelease::Releases.new(share)

  def home_file = File.join(@root, "home", "PLASTIC.md")

  def journal = InstallerRelease::Journal.new(share, releases, -> { [home_file] })

  def active = InstallerRelease::Pointer.new(File.join(share, "active"))

  def install(version)
    FileUtils.mkdir_p(releases.path(version))
    File.write(File.join(releases.path(version), "VERSION"), "#{version}\n")
    active.point_to(releases.pointer_target(version))
  end

  def setup
    super
    install("2.0.2")
    FileUtils.mkdir_p(File.dirname(home_file))
    File.write(home_file, "before\n")
  end

  def test_restore_puts_the_active_pointer_back
    journal.open
    install("2.0.3")
    journal.restore

    assert_equal "2.0.2", active.version
  end

  def test_restore_removes_a_release_the_activation_added
    journal.open
    install("2.0.3")
    journal.restore

    assert_equal %w[2.0.2], releases.versions
  end

  def test_restore_puts_the_home_back
    journal.open
    File.write(home_file, "after\n")
    journal.restore

    assert_equal "before\n", File.read(home_file)
  end

  def test_restore_removes_a_pointer_that_did_not_exist
    journal.open
    File.symlink("releases/2.0.2", File.join(share, "previous"))
    journal.restore

    refute File.symlink?(File.join(share, "previous"))
  end

  def test_a_discarded_journal_recovers_nothing
    journal.open
    install("2.0.3")
    journal.discard

    assert_equal [false, "2.0.3"], [journal.recover, active.version]
  end

  def test_a_journal_left_by_a_stopped_installer_is_recovered
    journal.open
    install("2.0.3")
    journal.recover

    assert_equal ["2.0.2", false], [active.version, File.directory?(File.join(share, "activation"))]
  end

  def test_a_journal_with_no_state_file_restores_nothing
    FileUtils.mkdir_p(File.join(share, "activation"))
    install("2.0.3")
    journal.restore

    assert_equal "2.0.3", active.version
  end
end
