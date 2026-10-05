# frozen_string_literal: true

require_relative "installer_helper"

class InstallReinstallTest < Plastic::TestCase
  include InstallerHelper

  def test_a_reinstall_without_agent_options_syncs_the_registered_agents
    %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
    call("install", "--codex")
    result = call("install", "--reinstall")

    assert_equal 0, result.code, result.err
    assert_path_exists File.join(@home, ".agents", "plastic", "manifest.json")
    refute_path_exists File.join(@home, ".claude", "plastic")
  end

  def test_a_reinstall_that_changes_nothing_reports_no_removed_hook_and_makes_no_offer
    %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
    call("install", "--claude", "--codex")
    result = call("install", "--reinstall")

    assert_equal 0, result.code, result.err
    assert_equal [false, false], [result.out.include?("Removed"), result.out.include?("Enola")], result.out
  end
end
