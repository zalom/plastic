# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/rollback_release"

class RollbackReleaseTest < Plastic::TestCase
  include InstallerHelper

  def roll(target: nil)
    env = { "PLASTIC_SHARE" => share }
    run_workflow(Plastic::Workflows::RollbackRelease, harness: scoped_harness(env:), target:)
  end

  def test_with_no_target_the_previous_release_goes_active
    activated("2.0.2", "2.0.3")

    outcome, context = roll

    assert_equal [:done, "2.0.2"], [outcome, context.switched]
    assert_equal %w[2.0.2 2.0.3], [activation.active_version, activation.previous_version]
  end

  def test_a_named_release_goes_active
    activated("2.0.1", "2.0.2", "2.0.3")

    roll(target: "2.0.1")

    assert_equal "2.0.1", activation.active_version
  end

  def test_the_switch_links_the_launcher_to_the_active_release
    activated("2.0.2", "2.0.3")

    roll

    assert_equal File.join(share, "active", "bin", "plastic"), File.readlink(File.join(@home, ".local", "bin", "plastic"))
  end
end
