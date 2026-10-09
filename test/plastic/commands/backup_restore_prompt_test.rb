# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup_restore"

# A stream the way a person's terminal is seen by the command: it answers tty?.
class TerminalInput < StringIO
  def tty? = true
end

class BackupRestorePromptTest < Plastic::TestCase
  include BackupHomes

  def sync_down(home) = plastic("sync", "down", "--project", "alpha", env: env_for(home), table: Plastic::CLI::TABLE)

  def intent_file(home) = File.join(home, "stores", "alpha", "store", "1--alpha", "intent.md")

  def edit_file(home) = File.write(intent_file(home), "\nWritten after the backup.\n", mode: "a")

  def edited_rows?(home)
    Plastic::Graph.open(home:, store: "alpha").retrieval.documents("1").any? { |doc| doc.body.include?("Written after the backup.") }
  end

  def edited_file?(home) = File.read(intent_file(home)).include?("Written after the backup.")

  def backed_up_home
    home = fresh_home
    sync_down(home)
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    home
  end

  def restore_answering(home, answers, *extra)
    input = TerminalInput.new(answers)
    [plastic("backup", "restore", "--store", "alpha", "--latest", *extra, env: env_for(home), table: Plastic::CLI::TABLE, input:), input]
  end

  def test_answering_down_prints_the_files_from_the_restored_rows
    home = backed_up_home
    File.delete(intent_file(home))
    result, = restore_answering(home, "down\n")

    assert_equal [0, true], [result.code, File.exist?(intent_file(home))]
  end

  def test_the_question_gives_one_line_for_each_answer
    result, = restore_answering(backed_up_home, "neither\n")

    assert_call result, code: 0, out: ["File edits made after the backup are lost", "replaces the restored row", "the rows and the files stay as they are"]
  end

  def test_answering_up_reads_the_files_newer_than_the_backup_into_the_rows
    home = backed_up_home
    edit_file(home)
    restore_answering(home, "up\n")

    assert edited_rows?(home)
  end

  def test_answering_neither_changes_no_row_and_no_file
    home = backed_up_home
    edit_file(home)
    result, = restore_answering(home, "neither\n")

    assert_equal [0, false, true], [result.code, edited_rows?(home), edited_file?(home)]
  end

  def test_an_unknown_answer_twice_counts_as_neither
    home = backed_up_home
    edit_file(home)
    result, = restore_answering(home, "maybe\nsoon\n")

    assert_equal [0, false, true], [result.code, edited_rows?(home), edited_file?(home)]
  end

  def test_an_unknown_answer_is_asked_again_once
    home = backed_up_home
    edit_file(home)
    restore_answering(home, "maybe\nup\n")

    assert edited_rows?(home)
  end

  def test_with_no_terminal_no_sync_runs_and_the_input_is_not_read
    home = backed_up_home
    edit_file(home)
    input = StringIO.new("up\n")
    result = plastic("backup", "restore", "--store", "alpha", "--latest", env: env_for(home), table: Plastic::CLI::TABLE, input:)

    assert_equal [0, 0, false], [result.code, input.pos, edited_rows?(home)]
  end

  def test_with_no_terminal_next_tells_the_agent_to_ask_with_both_explanations
    result = restore_call(backed_up_home, "--store", "alpha", "--latest")

    assert_call result, code: 0, out: ["next: ask the person", "File edits made after the backup are lost", "replaces the restored row"]
  end

  def test_a_preview_asks_nothing_and_syncs_nothing
    home = backed_up_home
    edit_file(home)
    result, input = restore_answering(home, "up\n", "--dry-run")

    assert_equal [0, 0, false], [result.code, input.pos, edited_rows?(home)]
  end

  def test_a_refused_restore_asks_nothing
    result, input = restore_answering(backed_up_home, "up\n", "--timestamp", "20200101000000")

    assert_equal [2, 0], [result.code, input.pos]
  end
end
