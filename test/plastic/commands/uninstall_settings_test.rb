# frozen_string_literal: true

require_relative "installer_helper"

class UninstallSettingsCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    claude_folder
    call("init", "1")
  end

  def test_restores_the_status_line_plastic_replaced
    original = { "type" => "command", "command" => "mine" }
    FileUtils.mkdir_p(File.join(@plastic_home, ".cache"))
    File.write(File.join(@plastic_home, ".cache", "original-statusline.json"), JSON.generate(original))
    edit_settings { |settings| settings.merge("statusLine" => { "type" => "command", "command" => plastic_statusline }) }
    call("install", "--reinstall")
    call("uninstall", "1")

    assert_equal original, settings["statusLine"]
  end

  def test_keeps_a_status_line_the_user_set
    edit_settings { |settings| settings.merge("statusLine" => { "type" => "command", "command" => "mine" }) }
    call("uninstall", "1")

    assert_equal "mine", settings.dig("statusLine", "command")
  end

  private

  def settings_path = File.join(claude_folder, "settings.json")

  def settings = JSON.parse(File.read(settings_path))

  def edit_settings = File.write(settings_path, JSON.generate(yield(settings)))

  def plastic_statusline = File.join(claude_folder, "plastic", "hooks", "plastic-statusline")
end
