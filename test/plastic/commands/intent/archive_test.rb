# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/link"
require_relative "../../../../lib/plastic/commands/intent/archive"

class IntentArchiveCaseTest < Plastic::TestCase
  def test_archiving_a_future_intent_prints_the_status_and_offers_the_board
    ran("intent new Later --status future")

    assert_case line("intent archive 1"), code: 0, out: ["intent: 1 archived", "next: plastic status"]
  end

  def test_archiving_an_open_intent_exits_1_and_names_the_end_command
    ran("intent new Alpha")

    assert_case line("intent archive 1"), code: 1, out: ["next: plastic intent end 1"],
      err: ["intent 1 is open; only done, abandoned and future intents archive"]
  end
end

class IntentArchiveTest < Plastic::TestCase
  def call(*args) = plastic("intent", "archive", *args, table: Plastic::CLI::TABLE)

  def mark_done(intent)
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :id", id: intent.intent_id)
    end
  end

  def add_ruling(intent)
    row = { intent_id: intent.intent_id, id: "D1", text: "a ruling", supersedes: nil, at: STAMP }
    store_graphs.databases.fetch(:knowledge).transaction { |batch| batch.put(:rulings, row, statement: :insert) }
  end

  def test_archiving_an_unlinked_done_intent_clears_the_folder
    intent = open_intent("Target")
    add_ruling(intent)
    mark_done(intent)

    result = call(intent.intent_id)

    assert_equal 0, result.code
    refute folder.exist?("#{intent.dir}/#{intent.file}")
  end

  def test_archiving_an_unlinked_done_intent_keeps_the_intent_row
    intent = open_intent("Target")
    mark_done(intent)

    call(intent.intent_id)

    assert retrieval.intent(intent.intent_id)
  end

  def test_archiving_an_unlinked_done_intent_keeps_its_document_and_ruling_bytes
    intent = open_intent("Target")
    add_ruling(intent)
    mark_done(intent)

    call(intent.intent_id)

    assert_equal intent.page(retrieval.origin_id), archived_document(intent).body
    assert_equal "a ruling", archived_ruling(intent).text
  end

  def test_an_open_intents_link_refuses_the_archive
    target = open_intent("Target")
    mark_done(target)
    linker = open_intent("Linker")
    plastic("intent", "link", linker.intent_id, "cites", target.intent_id, table: Plastic::CLI::TABLE)

    result = call(target.intent_id)

    assert_call result, code: 3, err: "plastic: refused, intent 2 links to 1\nThis step belongs to the owner. Stop and ask; do not retry with a flag.\n"
    assert folder.exist?("#{target.dir}/#{target.file}")
  end

  def test_an_open_intent_exits_1_naming_its_state_and_offers_intent_end
    intent = open_intent("Target")

    result = call(intent.intent_id)

    assert_equal [1, true], [result.code, result.err.include?("open")]
    assert_match(/^next: plastic intent end 1/, result.out)
  end

  def test_a_hand_edited_file_is_captured_before_archive
    intent = open_intent("Target")
    mark_done(intent)
    write("#{intent.dir}/#{intent.file}", "edited by hand\n")

    result = call(intent.intent_id)

    assert_equal 0, result.code
    refute folder.exist?("#{intent.dir}/#{intent.file}")
  end

  def test_an_archive_that_failed_fails_again_on_the_next_call
    intent = open_intent("Target")
    call(intent.intent_id)

    result = call(intent.intent_id)

    assert_equal 1, result.code
    refute retrieval.archived?(intent.intent_id)
  end

  def test_an_intent_refused_while_open_archives_once_it_is_done
    intent = open_intent("Target")
    call(intent.intent_id)
    mark_done(intent)

    result = call(intent.intent_id)

    assert_equal 0, result.code
    assert retrieval.archived?(intent.intent_id)
  end

  def test_archiving_an_archived_intent_finishes_idempotently
    intent = open_intent("Target")
    mark_done(intent)
    call(intent.intent_id)

    result = call(intent.intent_id)

    assert_equal 0, result.code
    assert retrieval.archived?(intent.intent_id)
  end

  def test_archiving_a_missing_intent_reports_a_failure
    result = call("99")

    assert_call result, code: 1, err: ["no intent 99"]
  end

  def test_a_date_archives_the_done_intent_closed_before_it
    intent = open_intent("Old")
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'done', closed_at = '2026-01-10T00:00:00Z' WHERE intent_id = :id", id: intent.intent_id)
    end

    result = call("--older-than", "2026-02-01")

    assert_equal [0, true], [result.code, retrieval.archived?(intent.intent_id)]
    assert_includes result.out, "intent: #{intent.intent_id} archived"
  end

  private

  def archived_document(intent) = retrieval.documents(intent.intent_id).find { |candidate| candidate.path == intent.file }

  def archived_ruling(intent) = retrieval.rulings(intent.intent_id).find { |candidate| candidate.id == "D1" }
end

module ArchiveFidelityFixtures
  def archive(intent, *options)
    plastic("intent", "archive", intent.intent_id, *options, table: Plastic::CLI::TABLE)
  end

  def unarchive(intent) = plastic("intent", "unarchive", intent.intent_id, table: Plastic::CLI::TABLE)

  def future_intent = open_intent("Snapshot", status: "future")

  def populated_intent
    future_intent.tap do |intent|
      root = folder.path(intent.dir)
      populate(root)
      stamp(root)
    end
  end

  def populate(root)
    File.binwrite("#{root}/.owner.lock", "\x00\xFFkeep".b)
    File.binwrite("#{root}/run", "#!/bin/sh\nexit 0\n")
    FileUtils.mkdir_p("#{root}/empty/nested")
    File.symlink("missing", "#{root}/dangling")
    File.symlink(".owner.lock", "#{root}/relative")
    File.chmod(0o751, "#{root}/run")
    File.chmod(0o750, root)
  end

  def stamp(root)
    Dir.glob("#{root}/**/*", File::FNM_DOTMATCH).reject { |path| File.basename(path) == "." }.each do |path|
      File.lutime(Time.at(1234), Time.at(1234), path)
    end
    File.utime(Time.at(1234), Time.at(1234), root)
  end

  def reverted_trees
    intent = populated_intent
    before = tree(folder.path(intent.dir))

    assert_archived(intent)
    assert_reverted(intent)
    [before, tree(folder.path(intent.dir))]
  end

  def tree(root)
    paths = [root, *Dir.glob("#{root}/**/*", File::FNM_DOTMATCH)].uniq.reject { |path| File.basename(path) == "." }
    paths.sort.to_h { |path| [path.delete_prefix(root), entry(path)] }
  end

  def entry(path)
    stat = File.lstat(path)
    [stat.ftype, stat.mode, stat.mtime, content(path, stat)]
  end

  def content(path, stat)
    return File.readlink(path) if stat.symlink?
    return File.binread(path) if stat.file?

    nil
  end

  def assert_archived(intent)
    result = archive(intent)

    assert_equal 0, result.code, result.err
    refute_path_exists folder.path(intent.dir)
  end

  def assert_reverted(intent)
    result = unarchive(intent)

    assert_equal 0, result.code, result.err
  end

  def replace_document_rows(intent)
    store_graphs.databases.fetch(:knowledge).transaction do |batch|
      batch.write(:documents, "UPDATE documents SET body = 'newer row' WHERE intent_id = :id", id: intent.intent_id)
    end
  end

  def archived_with_conflict
    populated_intent.tap do |intent|
      assert_archived(intent)
      File.symlink(folder.root, folder.path(intent.dir))
    end
  end
end

class ArchiveFidelityTest < Plastic::TestCase
  include ArchiveFidelityFixtures

  def test_revert_preserves_bytes_links_directories_modes_and_times
    before, after = reverted_trees

    assert_equal without_log(before), without_log(after)
  end

  def test_revert_keeps_the_work_log_and_adds_the_archived_and_unarchived_lines
    before, after = reverted_trees
    log = after.fetch("/work.log").last

    assert_equal [true, true], [log.start_with?(before.fetch("/work.log").last), log.match?(/archived - - Archived\n.*unarchived - - Unarchived\n\z/)]
  end

  def without_log(tree) = tree.except("", "/work.log")

  def test_revert_uses_snapshot_even_when_document_rows_change
    intent = future_intent
    path = "#{intent.dir}/#{intent.file}"
    write(path, "owner's unsynced text")

    assert_archived(intent)
    replace_document_rows(intent)

    assert_reverted(intent)

    assert_equal "owner's unsynced text", folder.read(path)
  end

  def test_archive_indexes_unsynced_text_before_removing_its_directory
    intent = future_intent
    write("#{intent.dir}/research.txt", "Archive-only evidence\n")

    assert_archived(intent)

    assert_equal [["research.txt", "Archive-only evidence\n"]], retrieval.search("archive evidence").map { |row| row.values_at("path", "body") }
  end

  def test_archive_keeps_an_unsupported_textual_attachment_without_failing
    intent = future_intent
    write("#{intent.dir}/report.pdf", "%PDF readable")

    assert_archived(intent)

    assert_empty retrieval.search("readable")
  end

  def test_revert_preserves_conflicting_symlink_and_archive_marker
    intent = archived_with_conflict

    assert_equal 1, unarchive(intent).code
    assert File.symlink?(folder.path(intent.dir))
    assert retrieval.archived?(intent.intent_id)
  end

  def test_archive_offers_status_instead_of_revert
    result = archive(future_intent)

    assert_equal 0, result.code
    assert_includes result.out, "next: plastic status"
    refute_includes Plastic::CLI::TABLE.keys, "intent restore"
  end

  def test_archive_reports_an_intent_directory_that_disappeared_before_capture
    intent = future_intent
    FileUtils.remove_entry(folder.path(intent.dir))

    result = archive(intent)

    assert_equal 1, result.code
    assert_includes result.err, "has no directory to archive"
  end
end

class ArchiveReadFidelityTest < Plastic::TestCase
  def test_archive_reads_return_snapshot_bytes_without_mutating_archive_state
    intent = archived_intent_with_unsynced_text
    before = archive_read_state(intent)

    assert_equal expected_bodies, read_bytes(intent)
    assert_equal before, archive_read_state(intent)
  end

  private

  def archived_intent_with_unsynced_text
    open_intent("Snapshot", status: "future").tap do |intent|
      write("#{intent.dir}/#{intent.file}", "Hand-edited archive evidence\n")
      write("#{intent.dir}/research.txt", "New archive evidence\n")
      result = plastic("intent", "archive", intent.intent_id, table: Plastic::CLI::TABLE)

      assert_equal 0, result.code, result.err
    end
  end

  def expected_rows(intent)
    [[intent.file, "Hand-edited archive evidence\n"], ["research.txt", "New archive evidence\n"]]
  end

  def expected_bodies = ["Hand-edited archive evidence\n", "New archive evidence\n"]

  def read_bytes(intent)
    assert_equal expected_rows(intent), retrieval.search("archive evidence").map { |row| row.values_at("path", "body") }.sort
    [retrieval.fetch(intent.intent_id, intent.file), retrieval.fetch(intent.intent_id, "research.txt")].map(&:body)
  end

  def archive_read_state(intent)
    work = store_graphs.databases.fetch(:work)
    archive_rows = work.rows("SELECT * FROM archives WHERE intent_id = :id ORDER BY intent_id", id: intent.intent_id)
    entry_rows = work.rows("SELECT * FROM archive_entries WHERE intent_id = :id ORDER BY path", id: intent.intent_id)
    changes = { work: work.rows("SELECT * FROM changes ORDER BY seq"),
                knowledge: store_graphs.databases.fetch(:knowledge).rows("SELECT * FROM changes ORDER BY seq") }
    { archive_rows:, entry_rows:, changes:, filesystem: filesystem_state(intent) }
  end

  def filesystem_state(intent)
    { exists: folder.exist?(intent.dir), files: snapshot(folder.path("store")) }
  end
end

class IntentArchivePreviewTest < Plastic::TestCase
  def seed_folder(home)
    seed_intents(home, "Target")
    mark_done_in(home, "1")
    folder = File.join(home, "stores", "global", "store", "1--target")
    File.write(File.join(folder, "notes.txt"), "notes")
    File.write(File.join(File.dirname(home), "outside.txt"), "outside")
    File.symlink(File.join(File.dirname(home), "outside.txt"), File.join(folder, "ref.txt"))
  end

  def test_an_archive_preview_lists_the_removed_files
    twin = twin_run("intent", "archive", "1") { |home| seed_folder(home) }
    folder = File.join(twin.first, "stores", "global", "store", "1--target")

    assert_equal [], twin.changed_paths
    assert_includes twin.preview_paths, "remove #{folder}/notes.txt"
    assert_includes twin.preview_paths, "remove #{folder}/intent.md"
  end

  def test_an_archive_preview_leaves_the_link_target_untouched
    twin = twin_run("intent", "archive", "1") { |home| seed_folder(home) }

    assert_equal "outside", File.read(File.join(File.dirname(twin.first), "outside.txt"))
  end

  def test_an_unarchive_preview_matches_apply_on_an_identical_home
    twin = twin_run("intent", "unarchive", "1") do |home|
      seed_intents(home, "Target")
      mark_done_in(home, "1")
      call_in(home, "intent", "archive", "1")
    end

    assert_preview_matches_apply(twin)
    assert_equal 0, twin.previewed.code
  end

  def test_an_unarchive_preview_of_an_intent_already_restored_fails_like_the_apply
    twin = twin_run("intent", "unarchive", "1") do |home|
      seed_intents(home, "Target")
      mark_done_in(home, "1")
      call_in(home, "intent", "archive", "1")
      call_in(home, "intent", "unarchive", "1")
    end

    assert_preview_matches_apply(twin)
  end
end

class IntentArchiveUsageTest < Plastic::TestCase
  def call(*args) = plastic("intent", "archive", *args, table: Plastic::CLI::TABLE)

  def test_naming_neither_an_intent_nor_a_date_is_a_usage_error
    result = call

    assert_equal [2, true], [result.code, result.err.include?("give an intent ID or --older-than DATE")]
  end

  def test_naming_both_an_intent_and_a_date_is_a_usage_error
    result = call("1", "--older-than", "2026-02-01")

    assert_equal [2, true], [result.code, result.err.include?("exclude each other")]
  end

  def test_a_date_that_is_not_a_date_is_a_usage_error
    result = call("--older-than", "last week")

    assert_equal [2, true], [result.code, result.err.include?("cannot read")]
  end
end
