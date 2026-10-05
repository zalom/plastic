# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/backup_restore"

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

  def test_a_name_the_backup_does_not_hold_refuses
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0), name: "work_graph")

    assert_nothing_changed home, restore_call(home, "--store", "alpha", "--timestamp", FIRST, "--name", "references"), "references"
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

  def test_name_restores_only_that_database
    home = seeded_home
    knowledge = bytes(home, "knowledge_graph")
    restore_call(home, "--store", "alpha", "--timestamp", FIRST, "--name", "work_graph")

    assert_equal [1, knowledge], [intent_count(home), bytes(home, "knowledge_graph")]
  end

  def test_restore_says_which_backup_holds_the_replaced_databases_and_what_to_run_next
    home = seeded_home
    result = restore_call(home, "--store", "alpha", "--timestamp", FIRST)

    assert_call result, code: 0, out: ["restore: backed up the current databases as", "next: plastic sync up --dry-run --project alpha"]
  end

  def test_a_preview_lists_the_databases_and_changes_nothing
    home = seeded_home
    before = [bytes(home, "work_graph", "knowledge_graph", "references"), folder_names(home)]
    result = restore_call(home, "--store", "alpha", "--timestamp", FIRST, "--dry-run")

    assert_call result, code: 0, out: ["preview", "work_graph", "knowledge_graph", "references", FIRST]
    assert_equal before, [bytes(home, "work_graph", "knowledge_graph", "references"), folder_names(home)]
  end

  def test_sync_up_after_restore_rereads_files_newer_than_the_backup
    home = fresh_home
    spec = Dir.glob(File.join(home, "stores", "alpha", "store", "*", "spec.md")).first
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    File.write(spec, "# Spec\n\nWritten after the backup.\n")
    restore_call(home, "--store", "alpha", "--latest")
    plastic("sync", "up", "--project", "alpha", env: env_for(home), table: Plastic::CLI::TABLE)

    body = Plastic::Graph.open(home:, store: "alpha").retrieval.documents("1").find { |document| document.path == "spec.md" }&.body
    assert_includes body, "Written after the backup."
  end
end
