# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/backup/restore"

class BackupRestoreTest < Plastic::TestCase
  include BackupHomes

  FIRST = "20260101100000"
  SECOND = "20260301093000"

  def seeded_home
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    add_intent(home)
    backup_at(home, at(2026, 3, 1, 9, 30, 0))
    add_intent(home)
    home
  end

  def bytes(home, *names) = names.map { |name| File.binread(store_file(home, name)) }

  def assert_nothing_changed(home, result, mention)
    before = bytes(home, "work_graph", "knowledge_graph")

    assert_refused_with_usage result, mention
    assert_equal before, bytes(home, "work_graph", "knowledge_graph")
  end

  def test_a_call_without_store_refuses_with_the_usage_line
    assert_refused_with_usage restore_call(fresh_home, "--latest"), "--store"
  end

  def test_an_unregistered_store_refuses_and_names_it
    assert_refused_with_usage restore_call(fresh_home, "--store", "nowhere", "--latest"), "nowhere"
  end

  def test_restore_with_neither_flag_refuses_and_changes_nothing
    home = seeded_home

    assert_nothing_changed home, restore_call(home, "--store", "alpha"), "--timestamp"
  end

  def test_restore_with_both_flags_refuses_and_changes_nothing
    home = seeded_home

    assert_nothing_changed home, restore_call(home, "--store", "alpha", "--latest", "--timestamp", FIRST), "--latest"
  end

  def test_a_missing_timestamp_refuses_and_names_it
    home = seeded_home

    assert_nothing_changed home, restore_call(home, "--store", "alpha", "--timestamp", "20200101000000"), "20200101000000"
  end

  def test_a_database_the_backup_does_not_hold_refuses
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0), databases: %w[work_graph])

    assert_nothing_changed home, restore_call(home, "--store", "alpha", "--timestamp", FIRST, "--databases", "references"), "references"
  end

  def mark_second(home, status)
    Plastic::Graph::Backup::Folders.new(File.join(home, "stores", "alpha")).write_report(SECOND, status:, goal: "full")
  end

  def test_a_database_name_that_is_unknown_refuses_and_names_it
    home = seeded_home

    assert_nothing_changed home, restore_call(home, "--store", "alpha", "--latest", "--databases", "nope"), "nope"
  end

  def test_a_comma_list_restores_each_listed_database
    home = seeded_home
    knowledge = bytes(home, "knowledge_graph")
    restore_call(home, "--store", "alpha", "--timestamp", FIRST, "--databases", "work_graph,work_graph")

    assert_equal [1, knowledge], [intent_count(home), bytes(home, "knowledge_graph")]
  end

  def test_latest_skips_a_backup_that_is_not_done
    home = seeded_home
    mark_second(home, "in-progress")
    restore_call(home, "--store", "alpha", "--latest")

    assert_equal 1, intent_count(home)
  end

  def test_timestamp_naming_a_backup_that_is_not_done_refuses_with_its_status
    home = seeded_home
    mark_second(home, "failed")
    before = bytes(home, "work_graph")
    result = restore_call(home, "--store", "alpha", "--timestamp", SECOND)

    assert_equal [3, ""], [result.code, result.out]
    assert_includes result.err, "failed"
    assert_equal before, bytes(home, "work_graph")
  end

  def test_latest_restores_the_newest_folder
    home = seeded_home

    assert_equal 0, restore_call(home, "--store", "alpha", "--latest").code
    assert_equal 2, intent_count(home)
  end

  def test_restore_brings_back_the_rows_of_the_backup
    home = seeded_home

    assert_equal 0, restore_call(home, "--store", "alpha", "--timestamp", FIRST).code
    assert_equal 1, intent_count(home)
  end

  def test_databases_restores_only_that_database
    home = seeded_home
    knowledge = bytes(home, "knowledge_graph")
    restore_call(home, "--store", "alpha", "--timestamp", FIRST, "--databases", "work_graph")

    assert_equal [1, knowledge], [intent_count(home), bytes(home, "knowledge_graph")]
  end

  def test_restore_says_which_backup_holds_the_replaced_databases_and_that_the_person_chooses_the_sync_direction
    home = seeded_home
    result = restore_call(home, "--store", "alpha", "--timestamp", FIRST)

    assert_call result, code: 0, out: ["restore: backed up the current databases as", "because: the rows are restored and the files are not; ask the person"]
  end

  def test_restoring_the_latest_with_no_done_backup_refuses_with_usage
    assert_refused_with_usage restore_call(fresh_home, "--store", "alpha", "--latest"), "no done backup of alpha to restore"
  end

  def test_a_preview_lists_the_databases_and_changes_nothing
    home = seeded_home
    before = [bytes(home, "work_graph", "knowledge_graph", "references"), folder_names(home)]
    result = restore_call(home, "--store", "alpha", "--timestamp", FIRST, "--dry-run")

    assert_call result, code: 0, out: ["preview", "work_graph", "knowledge_graph", "references", FIRST]
    assert_equal before, [bytes(home, "work_graph", "knowledge_graph", "references"), folder_names(home)]
  end
end

class BackupRestoreDeclarationTest < Minitest::Test
  def test_it_declares_that_it_writes_every_store_database_it_can_replace
    assert_equal Plastic::Graph::Schema.store.sort, Plastic::Commands::Backup::Restore.writes.uniq.sort
  end
end

class BackupRestoreGlobalTest < Plastic::TestCase
  include BackupHomes

  FIRST = "20260101100000"

  def test_restoring_the_global_store_replaces_its_own_databases
    home = fresh_home
    seed_store(home, "global")
    backup_at(home, at(2026, 1, 1, 10, 0, 0), slug: "global")
    add_intent(home, "global")

    assert_equal 0, restore_call(home, "--store", "global", "--timestamp", FIRST).code
    assert_equal 1, intent_count(home, "global")
  end
end

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

class BackupRestoreSyncTest < Plastic::TestCase
  include BackupHomes

  def sync(home, direction) = plastic("sync", direction, "--project", "alpha", env: env_for(home), table: Plastic::CLI::TABLE)

  def bodies(home) = Plastic::Graph.create(home:, store: "alpha").retrieval.documents("1").map(&:body)

  def test_sync_up_after_restore_rereads_files_newer_than_the_backup
    home = fresh_home
    sync(home, "down")
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    File.write(File.join(home, "stores", "alpha", "store", "1--alpha", "1--alpha.md"), "\nWritten after the backup.\n", mode: "a")
    restore_call(home, "--store", "alpha", "--latest")
    sync(home, "up")

    assert(bodies(home).any? { |body| body.include?("Written after the backup.") })
  end
end
