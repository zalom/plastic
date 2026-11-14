# frozen_string_literal: true

require_relative "../../commands/installer_helper"
require_relative "../../../../lib/plastic/workflows/code/update"

class UpdatePlasticTest < Plastic::TestCase
  include InstallerHelper

  def update(env: {}, **options)
    facts = { channel: nil }.merge(options)
    run_workflow(Plastic::Workflows::Code::Update, harness: scoped_harness(env: { "PLASTIC_SHARE" => share }.merge(env)), **facts)
  end

  def current(version) = { "PLASTIC_PACKAGE_ROOT" => fake_package(version) }

  def test_a_newer_package_is_synced_into_the_home
    installed("0.0.1")

    outcome, = update

    assert_equal :done, outcome
    assert_equal "#{package_version}\n", File.read(File.join(@plastic_home, "VERSION"))
  end

  def test_with_no_release_activated_it_names_install_sh_and_no_channel_variable
    installed("99.0.0-alpha.1")

    outcome, context = update(env: current("99.0.0-alpha.1"))

    assert_equal :fetch, outcome
    assert_equal "#{Plastic::Workflows::Installation::INSTALLER} sh", printed_row(context, "run:")
  end

  def test_a_newer_release_on_the_channel_is_downloaded_and_the_install_command_named
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    env = current("99.0.0-alpha.1").merge("PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.2"))

    outcome, context = update(env:)

    assert_equal [:downloaded, "99.0.0-alpha.2"], [outcome, context.release]
    assert_equal "99.0.0-alpha.1", activation.active_version
    assert_includes context.command, "--version 99.0.0-alpha.2"
  end

def test_a_home_with_only_a_release_from_install_sh_syncs_nothing_and_checks_for_a_newer_release
  activated("99.0.0-alpha.1")
  env = current("99.0.0-alpha.1").merge("PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.2"))

  outcome, = update(env:)

  assert_equal [:downloaded, false], [outcome, File.exist?(File.join(@plastic_home, "VERSION"))]
end

  def test_the_newest_active_release_stays_current
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    env = current("99.0.0-alpha.1").merge("PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.1"))

    outcome, = update(env:)

    assert_equal [:current, ["99.0.0-alpha.1"]], [outcome, activation.releases.versions]
  end
end
