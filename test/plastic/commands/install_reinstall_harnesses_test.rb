# frozen_string_literal: true

require_relative "installer_helper"

class InstallReinstallHarnessesTest < Plastic::TestCase
  include InstallerHelper

  def test_a_reinstall_syncs_the_installed_harnesses
    %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
    call("init", "2")
    FileUtils.rm_f(File.join(@home, ".codex", "agents", "plastic-executor.toml"))
    result = call("install", "--reinstall")

    assert_equal 0, result.code, result.err
    assert_equal [true, false], [File.exist?(File.join(@home, ".codex", "agents", "plastic-executor.toml")), File.exist?(File.join(@home, ".claude", "plastic"))]
  end

  def test_a_reinstall_syncs_an_existing_hermes_install
    claude_folder
    call("init", "1")
    FileUtils.mkdir_p(File.join(@home, ".hermes", "plastic"))
    File.write(File.join(@home, ".hermes", "plastic", "VERSION"), "2.0.0\n")
    call("install", "--reinstall")

    assert_path_exists File.join(@home, ".hermes", "plastic", "manifest.json")
  end
end
