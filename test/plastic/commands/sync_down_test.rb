# frozen_string_literal: true

require_relative "../../test_helper"

class SyncDownTest < Plastic::TestCase
  def sync_down = plastic("sync", "down", table: Plastic::CLI::TABLE)

  def archive(intent, *options)
    plastic("intent", "archive", intent.intent_id, *options, table: Plastic::CLI::TABLE)
  end

  def test_sync_down_offers_the_next_action_once_the_files_hold_the_rows
    open_intent

    assert_call sync_down, code: 0, out: "#{RUN_ROW}\nnext: plastic next --project global\nbecause: the files hold every row that changed\n"
  end

  def test_sync_down_after_an_archive_prints_nothing_back
    intent = open_intent("Target", status: "done")
    archive(intent)

    assert_call sync_down, code: 0,
      out: "printed store/index.json\n#{RUN_ROW}\nnext: plastic next --project global\nbecause: the files hold every row that changed\n"
    refute folder.exist?(intent.dir)
  end

  def test_a_file_changed_on_both_sides_is_refused_and_kept
    intent = open_intent("Unsynced", status: "future")
    path = "#{intent.dir}/#{intent.file}"
    archive(intent)
    archive(intent, "--revert")
    write(path, "owner edit after restore")

    result = sync_down

    assert_call result, code: 3, out: RUN_ROW, err: ["plastic: refused, changed on both sides since the last print, nothing written: #{path}"]
    assert_equal "owner edit after restore", folder.read(path)
  end
end
