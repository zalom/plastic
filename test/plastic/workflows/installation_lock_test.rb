# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/installation_health"

class InstallationLockTest < Plastic::TestCase
  def share = FileUtils.mkdir_p(File.join(@home, "share")).first

  def check = Plastic::Workflows::InstallationLock.new(share).check

  def test_a_share_with_no_lock_is_free
    assert_equal ["installer lock:", "free", nil], check.to_h.values
  end

  def test_a_lock_held_by_another_open_file_is_reported
    File.open(File.join(share, "INSTALL.lock"), "w") do |file|
      file.flock(File::LOCK_EX)

      assert_equal "held by a running installer", check.value
    end
  end

  def test_an_interrupted_activation_names_the_repair
    FileUtils.mkdir_p(File.join(share, "activation"))

    assert_equal Plastic::Workflows::InstallationLock::INTERRUPTED, check.repair
  end
end
