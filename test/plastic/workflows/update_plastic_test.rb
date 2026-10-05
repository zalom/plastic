# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/update_plastic"

class UpdatePlasticTest < Plastic::TestCase
  include InstallerHelper

  def update(env: {}, **channels)
    facts = { stable: false, beta: false, alpha: false }.merge(channels)
    run_workflow(Plastic::Workflows::UpdatePlastic, harness: scoped_harness(env: { "PLASTIC_SHARE" => share }.merge(env)), **facts)
  end

  def current(version) = { "PLASTIC_PACKAGE_ROOT" => fake_package(version) }

  def test_a_newer_package_is_synced_into_the_home
    installed("0.0.1")

    outcome, = update

    assert_equal :done, outcome
    assert_equal "#{package_version}\n", File.read(File.join(@plastic_home, "VERSION"))
  end

  def test_with_no_release_activated_it_names_the_installer_command
    installed("99.0.0-alpha.1")

    outcome, context = update(env: current("99.0.0-alpha.1"))

    assert_equal :fetch, outcome
    assert_equal "#{Plastic::Workflows::Installation::INSTALLER} PLASTIC_CHANNEL=alpha sh", printed_row(context, "run:")
  end

  def test_the_chosen_channel_goes_into_the_installer_command
    installed("99.0.0-alpha.1")

    _, context = update(env: current("99.0.0-alpha.1"), beta: true)

    assert_includes printed_row(context, "run:"), "PLASTIC_CHANNEL=beta"
  end

  def test_a_newer_release_on_the_channel_goes_active
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    env = current("99.0.0-alpha.1").merge("PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.2"))

    outcome, context = update(env:)

    assert_equal [:activated, "99.0.0-alpha.2"], [outcome, context.activated]
    assert_equal "99.0.0-alpha.2", activation.active_version
  end

  def test_the_newest_active_release_stays_current
    installed("99.0.0-alpha.1")
    activated("99.0.0-alpha.1")
    env = current("99.0.0-alpha.1").merge("PLASTIC_LOCAL_RELEASE" => local_release("99.0.0-alpha.1"))

    outcome, = update(env:)

    assert_equal [:current, ["99.0.0-alpha.1"]], [outcome, activation.releases.versions]
  end
end
