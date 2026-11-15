# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/backup/restore"

# A stream the way a person's terminal is seen by the command: it answers tty?.
class TerminalInput < StringIO
  def tty? = true
end

class BackupRestorePromptTest < Plastic::TestCase
  include BackupHomes

  BECAUSE = "the rows are restored and the files are not; ask the person whether to run plastic sync down, which writes the files from the rows, or plastic sync up, which reads the files into the rows"

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

def test_the_restore_ends_by_asking_the_person_which_way_to_sync_and_offers_no_command
  [TerminalInput.new(""), StringIO.new("")].each do |input|
    result = restore_with(backed_up_home, input)
    lines = result.out.lines(chomp: true)

    assert_equal [0, [], "because: #{BECAUSE}"], [result.code, lines.grep(/\Anext: /), lines.last]
  end
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
