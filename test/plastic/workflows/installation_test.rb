# frozen_string_literal: true

require_relative "../commands/installer_helper"
require "stringio"
require_relative "../../../scripts/lib/plastic/workflows/installation"
require_relative "../../../scripts/lib/plastic/installations"

class InstallationTest < Plastic::TestCase
  include InstallerHelper

  def installation(env: {}) = Plastic::Workflows::Installation.of(call_context(harness: scoped_harness(env:)))

  def test_the_agent_folders_sit_under_the_scope_home
    assert_equal File.join(@home, ".claude"), installation.agent_config("claude")[:dir]
  end

  def test_the_version_comes_from_the_package_json_of_the_package_root
    assert_equal "2.0.5", installation(env: { "PLASTIC_PACKAGE_ROOT" => fake_package("2.0.5") }).version
  end

  def test_a_reinstall_syncs_the_installed_harnesses_the_registry_names
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    call("init", "1")
    FileUtils.mkdir_p(File.join(@home, ".hermes", "plastic"))
    File.write(File.join(@home, ".hermes", "plastic", "VERSION"), "2.0.0\n")

    assert_equal ["codex"], installation.synced
  end

  def test_an_older_installed_version_makes_the_package_newer
    installed("0.0.1")

    assert_predicate installation(env: { "PLASTIC_PACKAGE_ROOT" => fake_package("2.0.5") }), :newer?
  end

  def installed_into(key)
    Plastic::Workflows::Installation.capture { installation.run(selected: [key], argv: [], input: StringIO.new) }
  end

  def test_an_install_into_a_registered_harness_writes_its_record
    claude_folder
    installed_into("claude")

    assert_includes Plastic::Installations.read(@plastic_home, "claude-code").files, File.join(@home, ".claude", "plastic", "manifest.json")
  end

  def test_an_install_into_an_unregistered_agent_writes_no_record
    FileUtils.mkdir_p(File.join(@home, ".hermes"))
    installed_into("hermes")

    assert_empty Dir.glob(File.join(Plastic::Installations.folder(@plastic_home), "*"))
  end

  def test_capture_hands_back_the_printed_lines
    assert_equal %w[one two], Plastic::Workflows::Installation.capture { puts "one\ntwo" }
  end
end
