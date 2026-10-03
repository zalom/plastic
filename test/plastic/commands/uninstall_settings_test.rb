# frozen_string_literal: true

require_relative "installer_helper"

class UninstallSettingsCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    claude_folder
    call("install", "--claude")
  end

  def test_restores_the_status_line_plastic_replaced
    original = { "type" => "command", "command" => "mine" }
    FileUtils.mkdir_p(File.join(@plastic_home, ".cache"))
    File.write(File.join(@plastic_home, ".cache", "original-statusline.json"), JSON.generate(original))
    edit_settings { |settings| settings.merge("statusLine" => { "type" => "command", "command" => plastic_statusline }) }
    call("uninstall", "--claude")

    assert_equal original, settings["statusLine"]
  end

  def test_keeps_a_status_line_the_user_set
    edit_settings { |settings| settings.merge("statusLine" => { "type" => "command", "command" => "mine" }) }
    call("uninstall", "--claude")

    assert_equal "mine", settings.dig("statusLine", "command")
  end

  def test_drops_the_plastic_plugin_and_an_empty_plugin_list
    edit_settings { |settings| settings.merge("enabledPlugins" => { "plastic@plastic" => true }) }
    call("uninstall", "--claude")

    refute settings.key?("enabledPlugins")
  end

  def test_keeps_the_other_enabled_plugins
    edit_settings { |settings| settings.merge("enabledPlugins" => { "plastic@plastic" => true, "mine@market" => true }) }
    call("uninstall", "--claude")

    assert_equal({ "mine@market" => true }, settings["enabledPlugins"])
  end

  private

  def settings_path = File.join(claude_folder, "settings.json")

  def settings = JSON.parse(File.read(settings_path))

  def edit_settings = File.write(settings_path, JSON.generate(yield(settings)))

  def plastic_statusline = File.join(claude_folder, "plastic", "hooks", "plastic-statusline")
end
