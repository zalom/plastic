# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/migration/kept_files_cleanup"

class KeptFilesCleanupTest < Plastic::TestCase
  Cleanup = Plastic::Graph::KeptFilesCleanup
  SyncSelection = Plastic::Graph::Knowledge::SyncSelection
  INSERT = "INSERT INTO sqlar (name, mode, mtime, sz, data, intent_id, sha256, origin_id) VALUES (?, 420, 0, 0, ?, ?, 's', 'o')"
  TMP = "store/1--alpha/resources/tmp/scratch.md"
  REPORT = "store/1--alpha/resources/output/reports/review.md"
  PAPER = "store/1--alpha/resources/references/paper.pdf"
  ROADMAP = "originals/roadmaps/plan.md"

  def setup
    super
    Plastic::Graph.create(home: @plastic_home, store: "alpha")
  end

  def root = File.join(@plastic_home, "stores", "alpha")

  def connection
    knowledge = File.join(root, "knowledge_graph.db")
    Plastic::Graph::Database::ConnectionPool.for(knowledge, attach: Plastic::Graph::Database::Store.attachments(knowledge))
  end

  def keep(name, data = "kept bytes", intent_id: "1") = connection.execute(INSERT, [name, SQLite3::Blob.new(data), intent_id])

  def clean(references: false) = Cleanup.new(connection, root, SyncSelection.new(types: %w[md html], references:, asked: [])).call

  def names = connection.execute("SELECT name FROM sqlar ORDER BY name").map { |row| row.fetch("name") }

  def on_disk(name) = File.join(root, name)

  def put_on_disk(name, text) = FileUtils.mkdir_p(File.dirname(on_disk(name))).then { File.write(on_disk(name), text) }

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

  def test_a_removed_row_whose_file_is_on_disk_leaves_the_file_as_it_is
    keep(TMP, "old scratch")
    put_on_disk(TMP, "new scratch")
    clean

    assert_equal [[], "new scratch"], [names, File.read(on_disk(TMP))]
  end

  def test_a_removed_row_of_an_archived_intent_is_not_printed_back
    keep(TMP)
    connection.execute("INSERT INTO archives (intent_id, at, origin_id) VALUES ('1', 'then', 'o')")
    clean

    assert_equal [[], false], [names, File.exist?(on_disk("store/1--alpha"))]
  end

  def test_a_removed_row_of_a_restored_intent_is_printed_back
    keep(TMP, "scratch")
    connection.execute("INSERT INTO archives (intent_id, at, origin_id, restored_at) VALUES ('1', 'then', 'o', 'later')")
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

  def test_a_cleanup_answers_the_number_of_rows_it_removed
    [REPORT, TMP, ROADMAP].each { |name| keep(name) }

    assert_equal 2, clean
  end
end
