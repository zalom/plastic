# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/installation"

class InstallationTest < Plastic::TestCase
  include InstallerHelper

  Choice = Struct.new(:claude, :codex, :hermes, :all, :reinstall, :scope)

  def choice(reinstall: false, **agents)
    Choice.new(claude: false, codex: false, hermes: false, all: false, reinstall:, scope: scoped_harness.scope, **agents)
  end

  def installation(env: {}) = Plastic::Workflows::Installation.of(call_context(harness: scoped_harness(env:)))

  def test_the_agent_folders_sit_under_the_scope_home
    assert_equal File.join(@home, ".claude"), installation.agent_config("claude")[:dir]
  end

  def test_the_version_comes_from_the_package_json_of_the_package_root
    assert_equal "2.0.5", installation(env: { "PLASTIC_PACKAGE_ROOT" => fake_package("2.0.5") }).version
  end

  def test_no_agent_chosen_selects_claude
    assert_equal ["claude"], Plastic::Workflows::Installation.selected(choice)
  end

  def test_all_selects_every_agent
    assert_equal %w[claude codex hermes], Plastic::Workflows::Installation.selected(choice(all: true))
  end

  def test_a_reinstall_with_no_agent_named_takes_the_registered_agents
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    call("install", "--codex")

    assert_equal ["codex"], Plastic::Workflows::Installation.to_install(choice(reinstall: true))
  end

  def test_an_older_installed_version_makes_the_package_newer
    installed("0.0.1")

    assert_predicate installation(env: { "PLASTIC_PACKAGE_ROOT" => fake_package("2.0.5") }), :newer?
  end

  def test_capture_hands_back_the_printed_lines
    assert_equal %w[one two], Plastic::Workflows::Installation.capture { puts "one\ntwo" }
  end
end
