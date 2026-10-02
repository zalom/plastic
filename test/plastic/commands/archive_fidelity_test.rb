# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_archive"

class ArchiveFidelityTest < Plastic::TestCase
  def archive(intent, *options)
    plastic("intent", "archive", intent.intent_id, *options, table: Plastic::CLI::TABLE)
  end

  def future_intent
    open_intent("Snapshot").tap do |intent|
      store_graphs.databases.fetch(:work).transaction do |batch|
        batch.write(:intents, "UPDATE intents SET status = 'future' WHERE intent_id = :id", id: intent.intent_id)
      end
    end
  end

  def populated_intent
    future_intent.tap do |intent|
      root = folder.path(intent.dir)
      File.binwrite("#{root}/.owner.lock", "\x00\xFFkeep".b)
      File.binwrite("#{root}/run", "#!/bin/sh\nexit 0\n")
      FileUtils.mkdir_p("#{root}/empty/nested")
      File.symlink("missing", "#{root}/dangling")
      File.symlink(".owner.lock", "#{root}/relative")
      File.chmod(0o751, "#{root}/run")
      File.chmod(0o750, root)
      Dir.glob("#{root}/**/*", File::FNM_DOTMATCH).reject { |path| File.basename(path) == "." }.each do |path|
        File.lutime(Time.at(1234), Time.at(1234), path)
      end
      File.utime(Time.at(1234), Time.at(1234), root)
    end
  end

  def tree(root)
    paths = [root, *Dir.glob("#{root}/**/*", File::FNM_DOTMATCH)].uniq.reject { |path| File.basename(path) == "." }
    paths.sort.to_h do |path|
      stat = File.lstat(path)
      body = stat.symlink? ? File.readlink(path) : (stat.file? ? File.binread(path) : nil)
      [path.delete_prefix(root), [stat.ftype, stat.mode, stat.mtime, body]]
    end
  end

  def test_revert_preserves_bytes_links_directories_modes_and_times
    intent = populated_intent
    before = tree(folder.path(intent.dir))

    assert_equal 0, archive(intent).code
    refute File.exist?(folder.path(intent.dir))
    assert_equal 0, archive(intent, "--revert").code
    assert_equal before, tree(folder.path(intent.dir))
  end

  def test_revert_uses_snapshot_even_when_document_rows_change
    intent = future_intent
    path = "#{intent.dir}/#{intent.file}"
    write(path, "owner's unsynced text")
    assert_equal 0, archive(intent).code
    store_graphs.databases.fetch(:knowledge).transaction do |batch|
      batch.write(:documents, "UPDATE documents SET body = 'newer row' WHERE intent_id = :id", id: intent.intent_id)
    end

    assert_equal 0, archive(intent, "--revert").code
    assert_equal "owner's unsynced text", folder.read(path)
  end

  def test_revert_preserves_conflicting_symlink_and_archive_marker
    intent = populated_intent
    assert_equal 0, archive(intent).code
    File.symlink(folder.root, folder.path(intent.dir))

    assert_equal 1, archive(intent, "--revert").code
    assert File.symlink?(folder.path(intent.dir))
    assert retrieval.archived?(intent.intent_id)
  end

  def test_archive_offers_status_instead_of_revert
    result = archive(future_intent)

    assert_equal 0, result.code
    assert_includes result.out, "next: plastic status"
    refute_includes Plastic::CLI::TABLE.keys, "intent restore"
  end
end
