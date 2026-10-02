# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_archive"

class ArchiveFidelityTest < Plastic::TestCase
  def archive(intent, *options)
    plastic("intent", "archive", intent.intent_id, *options, table: Plastic::CLI::TABLE)
  end

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
    result = archive(intent, "--revert")

    assert_equal 0, result.code, result.err
  end

  def test_revert_preserves_bytes_links_directories_modes_and_times
    intent = populated_intent
    before = tree(folder.path(intent.dir))

    assert_archived(intent)
    assert_reverted(intent)

    assert_equal before, tree(folder.path(intent.dir))
  end

  def replace_document_rows(intent)
    store_graphs.databases.fetch(:knowledge).transaction do |batch|
      batch.write(:documents, "UPDATE documents SET body = 'newer row' WHERE intent_id = :id", id: intent.intent_id)
    end
  end

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

    assert_equal 1, archive(intent, "--revert").code
    assert File.symlink?(folder.path(intent.dir))
    assert retrieval.archived?(intent.intent_id)
  end

  def archived_with_conflict
    populated_intent.tap do |intent|
      assert_archived(intent)
      File.symlink(folder.root, folder.path(intent.dir))
    end
  end

  def test_archive_offers_status_instead_of_revert
    result = archive(future_intent)

    assert_equal 0, result.code
    assert_includes result.out, "next: plastic status"
    refute_includes Plastic::CLI::TABLE.keys, "intent restore"
  end
end
