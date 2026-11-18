# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../commands/installer_helper"
require_relative "../../../lib/plastic/installations"

class CLIHarnessPickTest < Plastic::TestCase
  include InstallerHelper

  def test_a_home_with_no_harness_leaves_the_pick_with_no_change
    result = call("init", env: { "PATH" => "" })

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "no registered harness was found"
  end

  def test_found_harnesses_are_listed_for_the_person_to_pick
    FileUtils.mkdir_p(File.join(@home, ".claude"))

    assert_match(/1  \[x\] claude-code/, call("init", env: { "PATH" => "" }).out)
  end
end
