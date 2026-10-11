# frozen_string_literal: true

require_relative "installer_helper"

class UninstallCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    written_record("claude-code", ".claude")
  end

  def test_with_no_terminal_the_recorded_harnesses_are_listed_picked
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    result = call("uninstall")

    assert_equal [0, ""], [result.code, result.err]
    assert_match(/1  \[x\] claude-code\n.*2  \[ \] codex/m, result.out)
  end

  def test_with_no_terminal_the_next_step_asks_the_person_and_nothing_is_removed
    before = tree_snapshot(@home)
    result = call("uninstall", "--dry-run")

    assert_includes result.out, "next: plastic uninstall --dry-run <answer>"
    assert_equal before, tree_snapshot(@home)
  end

  def test_answering_q_removes_nothing
    before = tree_snapshot(@home)
    result = call("uninstall", "q")

    assert_equal [0, true], [result.code, result.out.include?("the person left with no change")]
    assert_equal before, tree_snapshot(@home)
  end

  def test_a_harness_with_no_record_is_named_and_left_alone
    FileUtils.mkdir_p(File.join(@home, ".codex"))
    before = tree_snapshot(@home)
    result = call("uninstall", "2")

    assert_equal [0, true], [result.code, result.out.include?("codex: no record lists what Plastic wrote")]
    assert_equal before, tree_snapshot(@home)
  end

  def test_with_no_harness_recorded_or_found_it_names_init
    FileUtils.rm_rf(File.join(@home, ".claude"))
    Plastic::Installations.delete(@plastic_home, "claude-code")
    result = call("uninstall", "1")

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "next: plastic init"
  end
end
