# frozen_string_literal: true

require_relative "installer_helper"

class InstallReinstallRecordTest < Plastic::TestCase
  include InstallerHelper

  def test_a_reinstall_writes_the_record_of_a_harness_installed_before_records
    claude_folder
    call("init", "1")
    FileUtils.rm_rf(Plastic::Installations.folder(@plastic_home))
    call("install", "--reinstall")

    assert_equal ["claude-code"], Plastic::Installations.recorded(@plastic_home)
  end
end
