# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/installer_core"

# Intent 301: every new script and library ships through the installer manifest.
class SessionCloseManifestTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)
  FILES = %w[
    scripts/hook-close scripts/file-session-intent scripts/promote-session-item
    scripts/lib/session_backfill.rb scripts/lib/session_close.rb
  ].freeze

  def installer
    @installer ||= InstallerCore.new(package_root: REPO)
  end

  def test_core_files_carries_every_301_file
    FILES.each { |rel| assert_includes installer.core_files.keys, rel }
  end

  def test_every_manifest_entry_exists_on_disk_and_scripts_are_executable
    FILES.each do |rel|
      path = File.join(REPO, rel)
      assert File.exist?(path), "manifest names #{rel}, which does not exist on disk"
      assert File.executable?(path), "#{rel} must be executable" unless rel.end_with?(".rb")
    end
    assert File.executable?(File.join(REPO, "hooks/close"))
  end
end
