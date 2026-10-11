# frozen_string_literal: true

require "json"
require_relative "installer_helper"
require_relative "../../../scripts/lib/plastic/installations"

class InitCommandTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
  end

  def test_with_no_terminal_the_found_harnesses_are_listed_picked
    result = call("init")

    assert_equal [0, ""], [result.code, result.err]
    assert_match(/1  \[x\] claude-code/, result.out)
    assert_match(/2  \[x\] codex/, result.out)
  end

  def test_with_no_terminal_the_next_step_asks_the_person_and_nothing_is_written
    before = tree_snapshot(@home)
    result = call("init")

    assert_includes result.out, "next: plastic init <answer>"
    assert_includes result.out, "ask the person"
    assert_equal before, tree_snapshot(@home)
  end

  def test_a_harness_is_found_by_its_program_on_the_path
    FileUtils.rm_rf(File.join(@home, ".codex"))
    bin = FileUtils.mkdir_p(File.join(@home, "bin")).first
    File.write(File.join(bin, "codex"), "#!/bin/sh\n")
    File.chmod(0o755, File.join(bin, "codex"))

    assert_match(/2  \[x\] codex/, call("init", env: { "PATH" => bin }).out)
  end

  def test_a_found_hermes_folder_is_listed_picked
    FileUtils.mkdir_p(File.join(@home, ".hermes"))

    assert_match(/3  \[x\] hermes/, call("init").out)
  end

  def test_answering_hermes_installs_into_it_and_writes_its_record
    FileUtils.mkdir_p(File.join(@home, ".hermes"))
    result = call("init", "3")

    assert_equal 0, result.code, result.err
    assert_equal [true, ["hermes"]], [File.exist?(File.join(@home, ".hermes", "plastic", "manifest.json")), Plastic::Installations.recorded(@plastic_home)]
  end

  def test_answering_1_installs_into_claude_code_only
    result = call("init", "1")

    assert_equal 0, result.code, result.err
    assert_path_exists File.join(@home, ".claude", "plastic", "manifest.json")
    refute_path_exists File.join(@home, ".codex", "hooks.json")
  end

  def test_answering_1_writes_the_record_of_claude_code_only
    call("init", "1")

    assert_equal ["claude-code"], Plastic::Installations.recorded(@plastic_home)
  end

  def test_answering_q_writes_nothing
    before = tree_snapshot(@home)
    result = call("init", "q")

    assert_equal 0, result.code, result.err
    assert_includes result.out, "the person left with no change"
    assert_equal before, tree_snapshot(@home)
  end

  def test_answering_a_installs_into_every_found_harness
    result = call("init", "a")

    assert_equal 0, result.code, result.err
    assert_equal %w[claude-code codex], Plastic::Installations.recorded(@plastic_home)
  end

  def test_an_answer_with_no_such_number_is_a_usage_error_that_writes_nothing
    before = tree_snapshot(@home)
    result = call("init", "3")

    assert_equal [2, true], [result.code, result.err.include?("no choice 3")]
    assert_equal before, tree_snapshot(@home)
  end

  def test_a_codex_install_tells_the_person_to_trust_the_hooks_in_codex
    result = call("init", "2")

    assert_equal 0, result.code, result.err
    assert_includes result.out, "run /hooks, and trust the changed Plastic hooks"
  end

  def test_the_installed_hooks_run_only_in_the_main_session
    call("init", "a")
    events = [File.join(@home, ".claude", "settings.json"), File.join(@home, ".codex", "hooks.json")]
      .flat_map { |path| JSON.parse(File.read(path)).fetch("hooks").keys }

    assert_empty events.grep(/Subagent/)
  end

  def test_with_no_harness_found_nothing_is_written_and_the_call_says_so
    %w[.claude .codex].each { |folder| FileUtils.rm_rf(File.join(@home, folder)) }
    before = tree_snapshot(@home)
    result = call("init")

    assert_equal [0, true], [result.code, result.out.include?("no registered harness was found")]
    assert_equal before, tree_snapshot(@home)
  end
end
