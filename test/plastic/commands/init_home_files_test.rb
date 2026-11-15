# frozen_string_literal: true

require "json"
require_relative "installer_helper"

class InitHomeFilesTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    claude_folder
  end

  def test_init_prints_plain_ascii
    result = call("init", "1")

    assert_equal 0, result.code, result.err
    assert_predicate result.out + result.err, :ascii_only?
  end

  def test_init_registers_no_check_update_hook
    call("init", "1")

    assert_equal [[], false], [settings.fetch("hooks", {}).values.flatten.grep(/check-update/), File.exist?(hook_file("plastic-check-update"))]
    refute_path_exists File.join(@plastic_home, "hooks", "check-update")
  end

  def test_init_copies_no_scripts_folder_and_denies_none
    call("init", "1")

    refute_path_exists File.join(@plastic_home, "scripts")
    assert_empty Array(settings.dig("permissions", "deny")).grep(/scripts/)
  end

  def test_init_writes_no_status_line_while_the_flag_is_unset
    call("init", "1")

    assert_equal [false, false], [settings.key?("statusLine"), File.exist?(hook_file("plastic-statusline"))]
  end

  def test_the_status_line_flag_on_writes_the_status_line_and_its_file
    call("init", "1")
    call("config", "set", "statusline", "true")
    call("install", "--reinstall")

    assert_equal [true, true], [settings.key?("statusLine"), File.exist?(hook_file("plastic-statusline"))]
  end

  def test_a_status_line_the_person_owns_stays_after_init
    own = { "type" => "command", "command" => "my-statusline" }
    File.write(File.join(@home, ".claude", "settings.json"), JSON.generate("statusLine" => own))
    call("init", "1")

    assert_equal own, settings["statusLine"]
  end

  def test_install_force_is_a_usage_error_and_writes_nothing
    result = call("install", "--force")

    assert_equal 2, result.code
    assert_includes result.err, "--force"
    assert_empty Dir.children(File.join(@home, ".claude"))
  end

  private

  def settings = JSON.parse(File.read(File.join(@home, ".claude", "settings.json")))

  def hook_file(name) = File.join(@home, ".claude", "hooks", name)
end
