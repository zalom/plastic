# frozen_string_literal: true

require_relative "installer_helper"

class RollbackCommandTest < Plastic::TestCase
  include InstallerHelper

  def test_says_when_there_is_no_version_history
    result = call("rollback")

    assert_equal 0, result.code
    assert_match(/no version history/, result.out)
  end

  def test_lists_the_version_history_and_marks_the_running_version
    installed("2.0.2", ledger: %w[2.0.1 2.0.2])
    result = call("rollback")

    assert_match(/history:\s+2\.0\.1 install/, result.out)
    assert_match(/history:\s+2\.0\.2 install .*\(installed\)/, result.out)
  end

  def test_names_the_installer_command_for_a_version_in_the_history
    installed("2.0.2", ledger: %w[2.0.1 2.0.2])
    before = tree_snapshot(@plastic_home)
    result = call("rollback", "--version", "2.0.1")

    assert_includes result.out, "PLASTIC_ARCHIVE_URL=https://github.com/zalom/plastic/releases/download/v2.0.1/plastic.tgz sh install.sh"
    assert_equal before, tree_snapshot(@plastic_home)
  end

  def test_refuses_a_version_outside_the_history
    installed("2.0.2", ledger: %w[2.0.2])
    result = call("rollback", "--version", "1.0.0")

    assert_equal 3, result.code
    assert_includes result.err, "1.0.0 is not in the version history"
  end
end
