# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/hook_launcher"

class HookLauncherTest < Plastic::TestCase
  HookLauncher = Plastic::Installations::HookLauncher

  def test_a_package_outside_the_releases_runs_the_launcher_copied_into_the_home
    launcher = HookLauncher.new("/work/plastic", "/h/.plastic")

    assert_equal ["/h/.plastic/exe/plastic", ["/h/.plastic/bin/plastic"]], [launcher.command, launcher.former]
  end

  def test_a_release_runs_the_active_launcher_and_names_both_former_launchers
    launcher = HookLauncher.new("/share/plastic/releases/2.0.3", "/h/.plastic")

    assert_equal ["/share/plastic/active/bin/plastic", ["/h/.plastic/bin/plastic", "/h/.plastic/exe/plastic"]],
      [launcher.command, launcher.former]
  end
end
