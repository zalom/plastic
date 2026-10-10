# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup_restore"

# A stream the way a person's terminal is seen by the command: it answers tty?.
class TerminalInput < StringIO
  def tty? = true
end

class BackupRestorePromptTest < Plastic::TestCase
  include BackupHomes

  NEXT = "plastic sync down --project alpha"

  def sync_down(home) = plastic("sync", "down", "--project", "alpha", env: env_for(home), table: Plastic::CLI::TABLE)

  def intent_file(home) = File.join(home, "stores", "alpha", "store", "1--alpha", "intent.md")

  def backed_up_home
    home = fresh_home
    sync_down(home)
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    File.write(intent_file(home), "\nWritten after the backup.\n", mode: "a")
    home
  end

  def restore_with(home, input)
    plastic("backup", "restore", "--store", "alpha", "--latest", env: env_for(home), table: Plastic::CLI::TABLE, input:)
  end

  def test_with_a_terminal_no_input_is_read_and_no_file_changes
    home = backed_up_home
    before = File.read(intent_file(home))
    input = TerminalInput.new("up\n")
    result = restore_with(home, input)

    assert_equal [0, 0, before], [result.code, input.pos, File.read(intent_file(home))]
  end

  def test_with_no_terminal_no_input_is_read_and_no_file_changes
    home = backed_up_home
    before = File.read(intent_file(home))
    input = StringIO.new("up\n")
    result = restore_with(home, input)

    assert_equal [0, 0, before], [result.code, input.pos, File.read(intent_file(home))]
  end

  def test_the_restore_ends_with_the_sync_down_line_with_a_terminal_and_without
    [TerminalInput.new(""), StringIO.new("")].each do |input|
      result = restore_with(backed_up_home, input)

      assert_call result, code: 0, out: ["next: #{NEXT}"]
      refute_match(/sync the restored store|answer down, up or neither|ask the person/, result.out)
    end
  end

  def test_the_line_it_ends_with_runs_as_written
    home = backed_up_home
    restore_with(home, StringIO.new(""))
    result = plastic("sync", "down", "--project", "alpha", env: env_for(home), table: Plastic::CLI::TABLE)

    assert_equal 0, result.code, result.err
  end

  def test_a_preview_reads_no_input_and_syncs_nothing
    home = backed_up_home
    before = File.read(intent_file(home))
    input = TerminalInput.new("up\n")
    result = plastic("backup", "restore", "--store", "alpha", "--latest", "--dry-run", env: env_for(home), table: Plastic::CLI::TABLE, input:)

    assert_equal [0, 0, before], [result.code, input.pos, File.read(intent_file(home))]
  end

  def test_a_refused_restore_reads_no_input
    input = TerminalInput.new("up\n")
    result = plastic("backup", "restore", "--store", "alpha", "--latest", "--timestamp", "20200101000000", env: env_for(backed_up_home), table: Plastic::CLI::TABLE, input:)

    assert_equal [2, 0], [result.code, input.pos]
  end
end
