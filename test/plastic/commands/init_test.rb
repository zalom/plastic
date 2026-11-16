# frozen_string_literal: true

require "json"
require_relative "installer_helper"
require_relative "../../../lib/plastic/installations"

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
    result = call("init", "4")

    assert_equal [2, true], [result.code, result.err.include?("no choice 4")]
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

class InitHomeFilesTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    claude_folder
  end

  def test_init_prints_plain_ascii
    result = call("init", "1")

    assert_equal 0, result.code, result.err
    assert_predicate result.out + result.err, :ascii_only?
  end

  def test_init_registers_no_check_update_hook
    call("init", "1")

    assert_equal [[], false], [settings.fetch("hooks", {}).values.flatten.grep(/check-update/), File.exist?(hook_file("plastic-check-update"))]
    refute_path_exists File.join(@plastic_home, "hooks", "check-update")
  end

  def test_init_copies_no_scripts_folder_and_denies_none
    call("init", "1")

    refute_path_exists File.join(@plastic_home, "scripts")
    assert_empty Array(settings.dig("permissions", "deny")).grep(/scripts/)
  end

  def test_init_writes_no_status_line_while_the_flag_is_unset
    call("init", "1")

    assert_equal [false, false], [settings.key?("statusLine"), File.exist?(hook_file("plastic-statusline"))]
  end

  def test_the_status_line_flag_on_writes_the_status_line_and_its_file
    call("init", "1")
    call("config", "set", "statusline", "true")
    call("install", "--reinstall")

    assert_equal [true, true], [settings.key?("statusLine"), File.exist?(hook_file("plastic-statusline"))]
  end

  def test_a_status_line_the_person_owns_stays_after_init
    own = { "type" => "command", "command" => "my-statusline" }
    File.write(File.join(@home, ".claude", "settings.json"), JSON.generate("statusLine" => own))
    call("init", "1")

    assert_equal own, settings["statusLine"]
  end

  def test_install_force_is_a_usage_error_and_writes_nothing
    result = call("install", "--force")

    assert_equal 2, result.code
    assert_includes result.err, "--force"
    assert_empty Dir.children(File.join(@home, ".claude"))
  end

  private

  def settings = JSON.parse(File.read(File.join(@home, ".claude", "settings.json")))

  def hook_file(name) = File.join(@home, ".claude", "hooks", name)
end

class InitMediaSyncTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    %w[.claude .codex].each { |folder| FileUtils.mkdir_p(File.join(@home, folder)) }
  end

  def media_setting = Plastic::Config.new(@plastic_home).flag(%w[sync media], default: nil)

  def test_with_no_terminal_the_sync_of_images_and_videos_is_listed_picked_after_the_harnesses
    assert_match(/3  \[x\] sync images and videos/, call("init").out)
  end

  def test_once_the_sync_of_images_and_videos_is_off_it_is_listed_not_picked
    Plastic::Config.new(@plastic_home).set("sync.media", false)

    assert_match(/3  \[ \] sync images and videos/, call("init").out)
  end

  def test_answering_every_choice_turns_the_sync_of_images_and_videos_on
    result = call("init", "a")

    assert_equal [0, true], [result.code, media_setting]
  end

  def test_answering_a_harness_alone_turns_the_sync_of_images_and_videos_off
    result = call("init", "1")

    assert_equal [0, false], [result.code, media_setting]
  end

  def test_answering_the_images_and_videos_row_alone_installs_nothing
    before = tree_snapshot(@home)
    result = call("init", "3")

    assert_equal [0, true], [result.code, result.out.include?("the person left with no change")]
    assert_equal before, tree_snapshot(@home)
  end
end
