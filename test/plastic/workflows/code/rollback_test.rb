# frozen_string_literal: true

require_relative "../../commands/installer_helper"
require_relative "../../../../lib/plastic/workflows/code/rollback"

class RollbackReleaseTest < Plastic::TestCase
  include InstallerHelper

  def roll(target: nil)
    env = { "PLASTIC_SHARE" => share }
    run_workflow(Plastic::Workflows::Code::Rollback, harness: scoped_harness(env:), target:)
  end

  def test_with_no_target_the_command_switches_to_the_previous_release
    activated("2.0.2", "2.0.3")

    outcome, context = roll

    assert_equal :done, outcome
    assert_match(/--switch 2\.0\.2 /, context.command)
  end

  def test_a_named_release_is_the_one_the_command_switches_to
    activated("2.0.1", "2.0.2", "2.0.3")

    _, context = roll(target: "2.0.1")

    assert_match(/--switch 2\.0\.1 /, context.command)
  end

  def test_the_workflow_changes_no_active_release
    activated("2.0.2", "2.0.3")

    roll

    assert_equal %w[2.0.3 2.0.2], [activation.active_version, activation.previous_version]
  end
end
