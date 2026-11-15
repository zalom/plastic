# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/cli"
require "shellwords"
require_relative "../commands/installer_helper"
require_relative "../../test_helpers/backup_homes"

class ResultTest < Minitest::Test
  def result(command = "plastic next")
    Plastic::CLI::Result.new.tap { |answer| answer.offer(command, "a rule") }
  end

  def test_a_scoped_command_keeps_the_project_the_call_named
    assert_equal "plastic node claim 1 n1 --project my\\ app", result("plastic node claim 1 n1").next_command("my app")
  end

  def test_a_command_that_names_its_project_is_left_alone
    assert_equal "plastic next --project a", result("plastic next --project a").next_command("b")
  end

  def test_an_unscoped_command_never_gains_a_project
    assert_equal "plastic help", result("plastic help").next_command("a")
  end

  def test_a_command_the_scoped_list_no_longer_names_never_gains_a_project
    assert_equal "plastic continue", result("plastic continue").next_command("a")
    assert_equal "plastic query x", result("plastic query x").next_command("a")
  end

  def test_with_no_next_step_there_are_no_closing_lines
    assert_empty Plastic::CLI::Result.new.closing_lines("a")
  end

  def test_the_closing_lines_are_next_and_because
    assert_equal ["next: plastic next", "because: a rule"], result.closing_lines(nil)
  end

  def test_the_json_answer_drops_the_label_colon_and_carries_the_lines
    answer = result
    answer.row("node:", "n1")
    answer.line("raw")

    assert_equal({ "result" => { "node" => "n1", "output" => ["raw"] }, "next" => "plastic next", "because" => "a rule" }, answer.document(nil))
  end
end

class DryRunNextTest < Plastic::TestCase
  include InstallerHelper
  include BackupHomes

  PROJECT = %w[--project global].freeze

  def printed_words(result)
    line = result.out.lines(chomp: true).grep(/\Anext: /).fetch(0)
    words = Shellwords.split(line.delete_prefix("next: "))
    words - PROJECT
  end

  def assert_next_is_the_call(argv, result, env: {})
    assert_equal 0, result.code, result.err
    assert_equal ["plastic", *(argv - ["--dry-run"])].sort, printed_words(result).sort
    refute_includes printed_words(result), "--dry-run", env.to_s
  end

  def test_backup_keeps_its_databases_option
    home = fresh_home
    argv = ["backup", "--store", "alpha", "--databases", "work_graph", "--dry-run"]

    assert_next_is_the_call argv, call(*argv, env: env_for(home))
  end

  def test_backup_purge_keeps_its_filter
    home = fresh_home
    argv = ["backup", "purge", "--store", "alpha", "--older-than", "2026-01-01", "--dry-run"]

    assert_next_is_the_call argv, call(*argv, env: env_for(home))
  end

  def test_backup_restore_keeps_its_timestamp
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    argv = ["backup", "restore", "--store", "alpha", "--timestamp", "20260101100000", "--dry-run"]

    assert_next_is_the_call argv, call(*argv, env: env_for(home))
  end

  def test_install_keeps_its_reinstall_switch
    argv = ["install", "--reinstall", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_update_keeps_its_channel
    installed("0.0.1")
    argv = ["update", "--channel", "stable", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_rollback_keeps_the_call
    activated("2.0.2", "2.0.3")
    argv = ["rollback", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_uninstall_keeps_its_answer
    claude_folder
    call("init", "1")
    argv = ["uninstall", "--dry-run", "1"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_sync_up_keeps_the_call
    argv = ["sync", "up", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_sync_down_keeps_the_call
    argv = ["sync", "down", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end

  def test_intent_revise_offers_the_call_without_the_dry_run
    call("intent", "new", "Alpha")
    argv = ["intent", "revise", "1", "Beta", "--dry-run"]

    assert_next_is_the_call argv, call(*argv)
  end
end

class FilesRowTest < Plastic::TestCase
  include LifecycleHelper

  def run_cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def files_of(call) = JSON.parse(call.out).dig("result", "files")

  def add_node(*options) = run_cli("node", "add", "1", "first", "--criterion", "done", *options)

  def test_a_writing_call_names_the_files_it_printed_relative_to_the_store_folder
    intent = open_keyed_intent

    result = add_node("--json")

    assert_includes files_of(result), "#{intent.dir}/graph.json"
    assert_empty(files_of(result).select { |path| path.start_with?("/") })
  end

  def test_the_text_answer_lists_the_files_under_one_label
    intent = open_keyed_intent

    result = add_node

    assert_match(%r{^files:  +store/}, result.out)
    assert_includes result.out, "#{intent.dir}/graph.json"
  end

  def test_no_line_starts_with_printed
    open_keyed_intent

    assert_empty(add_node.out.lines.grep(/^printed /))
  end

  def test_a_call_that_printed_nothing_carries_an_empty_list_in_json_and_no_row_in_text
    open_keyed_intent
    add_node

    assert_equal [], files_of(run_cli("graph", "show", "1", "--json"))
    assert_empty(run_cli("graph", "show", "1").out.lines.grep(/^files:/))
  end

  def test_a_refused_write_lists_no_files
    open_keyed_intent

    result = run_cli("node", "add", "9", "first", "--criterion", "done")

    assert_empty(result.out.lines.grep(/^files:/))
  end

  def test_sync_down_lists_its_files_under_files_and_prints_no_printed_line
    intent = open_keyed_intent
    File.delete(store_path("#{intent.dir}/graph.json"))

    result = run_cli("sync", "down")

    assert_empty(result.out.lines.grep(/^printed /))
    assert_match(%r{^files:\s+#{Regexp.escape(intent.dir)}/graph\.json$}, result.out)
  end

  def test_a_json_answer_with_no_graph_write_still_carries_files
    open_keyed_intent
    run_cli("sync", "down")

    assert_equal [], files_of(run_cli("sync", "down", "--json"))
  end
end
