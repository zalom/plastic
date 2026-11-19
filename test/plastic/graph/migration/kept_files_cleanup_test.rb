# frozen_string_literal: true

require "digest"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/kept_files_cleanup"
require_relative "../../../../lib/plastic/graph/migration/file_print"

module KeptFilesCleanupCases
  Cleanup = Plastic::Graph::KeptFilesCleanup
  SyncSelection = Plastic::Graph::Knowledge::SyncSelection
  INSERT = "INSERT INTO sqlar (name, mode, mtime, sz, data, intent_id, sha256, origin_id) VALUES (?, 420, 0, 0, ?, ?, ?, 'o')"
  TMP = "store/1--alpha/resources/tmp/scratch.md"
  REPORT = "store/1--alpha/resources/output/reports/review.md"
  PAPER = "store/1--alpha/resources/references/paper.pdf"
  ROADMAP = "originals/roadmaps/plan.md"

  def setup
    super
    Plastic::Graph.create(home: @plastic_home, store: "alpha")
    connection.execute("INSERT INTO intents (intent_id, origin_id, slug, title, status) VALUES ('1', 'o', 'alpha', 'Alpha', 'open')")
    FileUtils.mkdir_p(on_disk("store/1--alpha"))
  end

  def root = File.join(@plastic_home, "stores", "alpha")

  def connection
    knowledge = File.join(root, "knowledge_graph.db")
    Plastic::Graph::Database::ConnectionPool.for(knowledge, attach: Plastic::Graph::Database::Store.attachments(knowledge))
  end

  def keep(name, data = "kept bytes", intent_id: "1")
    connection.execute(INSERT, [name, SQLite3::Blob.new(data), intent_id, Digest::SHA256.hexdigest(data)])
  end

  def selection(references: false) = SyncSelection.new(types: %w[md html], references:, asked: [])

  def clean(references: false, **options) = Cleanup.new(connection, root, selection(references:), **options).call

  def names = connection.execute("SELECT name FROM sqlar ORDER BY name").map { |row| row.fetch("name") }

  def on_disk(name) = File.join(root, name)

  def put_on_disk(name, text) = FileUtils.mkdir_p(File.dirname(on_disk(name))).then { File.write(on_disk(name), text) }

  def archive(entry: nil, restored_at: nil)
    connection.execute("INSERT INTO archives (intent_id, at, origin_id, restored_at) VALUES ('1', 'then', 'o', ?)", [restored_at])
    FileUtils.rm_rf(on_disk("store/1--alpha")) unless restored_at
    return unless entry

    connection.execute("INSERT INTO archive_entries (intent_id, path, origin_id, kind, mode, mtime, data) VALUES ('1', 'resources/tmp/scratch.md', 'o', 'file', 420, 'then', ?)",
      [SQLite3::Blob.new(entry)])
  end
end

class KeptFilesCleanupTest < Plastic::TestCase
  include KeptFilesCleanupCases

  def test_a_row_the_sync_reads_stays_and_a_row_it_never_reads_goes
    [REPORT, TMP].each { |name| keep(name) }
    clean

    assert_equal [REPORT], names
  end

  def test_a_row_under_references_stays_when_the_machine_reads_references
    [PAPER, TMP].each { |name| keep(name) }
    clean(references: true)

    assert_equal [PAPER], names
  end

  def test_a_removed_row_whose_file_is_gone_is_printed_back_to_its_path_first
    keep(ROADMAP, "old roadmap", intent_id: nil)
    clean

    assert_equal [[], "old roadmap"], [names, File.read(on_disk(ROADMAP))]
  end

  def test_a_removed_row_whose_file_on_disk_has_its_bytes_goes_and_leaves_the_file_as_it_is
    keep(TMP, "same scratch")
    put_on_disk(TMP, "same scratch")
    clean

    assert_equal [[], "same scratch"], [names, File.read(on_disk(TMP))]
  end

  def test_a_row_whose_file_on_disk_differs_stays_and_is_reported
    keep(TMP, "old scratch")
    put_on_disk(TMP, "new scratch")
    result = clean

    assert_equal [[TMP], "new scratch", { TMP => "the file on disk differs" }], [names, File.read(on_disk(TMP)), result.kept]
  end

  def test_a_row_whose_file_on_disk_is_empty_stays
    keep(TMP, "the only full copy")
    put_on_disk(TMP, "")
    clean

    assert_equal [TMP], names
  end

  def test_a_row_of_an_archived_intent_whose_archive_holds_no_copy_stays_and_is_reported
    keep(TMP)
    archive
    result = clean

    assert_equal [[TMP], false, { TMP => "intent 1 is archived and its archive holds no copy of it" }], [names, File.exist?(on_disk("store/1--alpha")), result.kept]
  end

  def test_a_row_of_an_archived_intent_whose_archive_holds_its_bytes_goes_and_nothing_is_printed
    keep(TMP, "archived scratch")
    archive(entry: "archived scratch")
    clean

    assert_equal [[], false], [names, File.exist?(on_disk("store/1--alpha"))]
  end

  def test_a_row_of_an_archived_intent_whose_archive_holds_other_bytes_stays
    keep(TMP, "the newer scratch")
    archive(entry: "the older scratch")
    clean

    assert_equal [TMP], names
  end

  def test_a_removed_row_of_a_restored_intent_is_printed_back
    keep(TMP, "scratch")
    archive(restored_at: "later")
    clean

    assert_equal "scratch", File.read(on_disk(TMP))
  end

  def test_a_name_that_leads_outside_the_store_folder_is_refused_and_nothing_is_written_or_removed
    keep("../outside.md", "outside")
    keep(ROADMAP, "old roadmap", intent_id: nil)

    error = assert_raises(Cleanup::Refused) { clean }

    assert_equal ["the kept file ../outside.md leads outside the store folder", [ROADMAP, "../outside.md"].sort, false, false],
      [error.message, names, File.exist?(File.join(root, "..", "outside.md")), File.exist?(on_disk(ROADMAP))]
  end

  def test_a_cleanup_answers_the_number_of_rows_it_removed_and_the_rows_it_kept
    [REPORT, TMP, ROADMAP].each { |name| keep(name) }
    put_on_disk(TMP, "changed")
    result = clean

    assert_equal [1, [TMP]], [result.removed, result.kept.keys]
  end
end

class KeptFilesPrintTest < Plastic::TestCase
  include KeptFilesCleanupCases

  # Stands in for a write that leaves other bytes on the disk than it was given.
  WRONG_PRINT = ->(path, _bytes) { FileUtils.mkdir_p(File.dirname(path)).then { File.binwrite(path, "other bytes") } }

  # Bytes whose write fails part way, as on a full disk.
  FAILING_BYTES = Class.new { def to_s = raise(Errno::ENOSPC) }.new

  def test_a_printed_back_file_leaves_no_other_file_in_its_folder
    keep(TMP, "scratch")
    clean

    assert_equal ["scratch.md"], Dir.children(File.dirname(on_disk(TMP)))
  end

  def test_a_printed_copy_whose_hash_differs_keeps_the_row_and_leaves_no_file
    keep(TMP, "scratch")
    result = clean(printer: WRONG_PRINT)

    assert_equal [[TMP], { TMP => "the printed copy differs" }, false], [names, result.kept, File.exist?(on_disk(TMP))]
  end

  def test_a_print_that_fails_part_way_leaves_nothing_in_the_folder
    folder = Dir.mktmpdir

    assert_raises(Errno::ENOSPC) { Plastic::Graph::FilePrint.call(File.join(folder, "plan.md"), FAILING_BYTES) }
    assert_empty Dir.children(folder)
  end

  def test_a_print_writes_the_bytes_at_the_path
    path = File.join(Dir.mktmpdir, "plan.md")
    Plastic::Graph::FilePrint.call(path, "the bytes")

    assert_equal "the bytes", File.read(path)
  end
end

class KeptFilesFolderTest < Plastic::TestCase
  include KeptFilesCleanupCases

  RENAMED = "store/1--old-name/resources/tmp/scratch.md"
  GONE = "store/2--gone/resources/tmp/scratch.md"

  def sync_up = plastic("sync", "up", "--project", "alpha", table: Plastic::CLI::TABLE)

  def test_a_row_of_a_folder_no_intent_holds_stays_and_the_folder_is_not_made
    keep(RENAMED)
    result = clean

    assert_equal [[RENAMED], false, { RENAMED => "its intent folder store/1--old-name is not on disk with an intent row" }],
      [names, File.exist?(on_disk("store/1--old-name")), result.kept]
  end

  def test_a_row_of_an_intent_whose_folder_is_gone_stays_and_the_folder_is_not_made
    connection.execute("INSERT INTO intents (intent_id, origin_id, slug, title, status) VALUES ('2', 'o', 'gone', 'Gone', 'open')")
    keep(GONE, intent_id: "2")
    clean

    assert_equal [[GONE], false], [names, File.exist?(on_disk("store/2--gone"))]
  end

  def test_a_row_of_an_existing_intent_folder_is_printed_into_its_new_subfolders
    keep(TMP, "scratch")
    clean

    assert_equal [[], "scratch"], [names, File.read(on_disk(TMP))]
  end

  def test_a_sync_of_the_store_passes_after_a_cleanup_that_kept_a_row_of_a_gone_folder
    keep(RENAMED)
    clean
    Plastic::Graph::Database::ConnectionPool.release(root)

    result = sync_up

    assert_equal [0, ""], [result.code, result.err]
  end
end
