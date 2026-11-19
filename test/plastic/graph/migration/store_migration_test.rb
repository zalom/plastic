# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/beta_2_store"
require_relative "../../../test_helpers/schema_versions"
require_relative "../../../../lib/plastic/graph/migration/runner"
require_relative "../../../../lib/plastic/graph/knowledge/sync_selection"

module StoreMigrationRuns
  include Beta2Store
  include SchemaVersions

  Runner = Plastic::Graph::SchemaRunner
  NOW = Time.utc(2026, 1, 1)
  SELECTION = Plastic::Graph::Knowledge::SyncSelection.new(types: %w[md html], references: false, asked: [])

  def migrate(home) = Runner.new(home:, now: NOW, selection: SELECTION, released: Plastic::Graph::MIGRATIONS.held(:store)).call

  def migrated_home(**options) = beta_2_home(**options).tap { |home| migrate(home) }

  def knowledge(home, sql) = read_file(store_path(home, "knowledge_graph.db"), sql)

  def work(home, sql) = read_file(store_path(home, "work_graph.db"), sql)

  def fresh_layouts
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")
    layouts_of(store_root(home))
  end
end

class StoreMigrationTest < Plastic::TestCase
  include StoreMigrationRuns
  include BackupHomes

  def test_the_store_migrates_and_each_table_has_the_names_and_columns_of_a_new_store
    home = beta_2_home
    report = migrate(home)

    assert_equal [["alpha"], {}], [report.migrated, report.failed]
    assert_equal fresh_layouts, layouts_of(store_root(home))
  end

  def test_the_knowledge_file_records_every_store_version_as_in_a_new_store
    home = migrated_home

    assert_equal [Plastic::Graph::MIGRATIONS.versions(:store), nil, nil], %w[knowledge_graph work_graph retrieval_graph].map { |name| recorded_versions(store_path(home, "#{name}.db")) }
  end

  def test_the_intent_tables_move_to_knowledge_with_their_values_in_the_named_columns
    home = migrated_home

    assert_equal [[1, "First", nil, "in_progress"], [2, "Second", "shipped", "done"]], knowledge(home, "SELECT id, title, reason, status FROM intents ORDER BY id")
    assert_equal [1, 1, 1, 1, 1, 1], %w[clusters completions approvals verdicts archives archive_entries].map { |table| knowledge(home, "SELECT count(*) FROM #{table}").flatten.first }
    assert_equal [[[0x00, 0xff, 0x10].pack("C*")]], knowledge(home, "SELECT data FROM archive_entries").map { |row| [row.first.b] }
  end

  def test_the_work_file_no_longer_holds_the_tables_that_moved_or_went
    home = migrated_home
    names = work(home, "SELECT name FROM sqlite_master WHERE type = 'table'").flatten

    assert_empty names & %w[intents clusters completions approvals verdicts archives archive_entries savepoints printed changes]
  end

  def test_the_intents_sequence_carries_over_even_above_the_highest_row
    home = migrated_home

    assert_equal [[3]], knowledge(home, "SELECT seq FROM sqlite_sequence WHERE name = 'intents'")
  end

  def test_each_claimed_node_keeps_its_agent_and_each_agent_node_gets_a_run
    home = migrated_home

    assert_equal [["n1", "agent-1"], ["n2", nil], ["n3", nil]], work(home, "SELECT id, claimed_by FROM nodes ORDER BY id")
    assert_equal [["n1", 1, "agent-1"], ["n2", 1, "agent-2"]], work(home, "SELECT node_id, number, session_id FROM runs ORDER BY node_id")
  end

  def test_the_savepoints_become_the_work_log_in_order
    home = migrated_home

    assert_equal [[1, "noted", "first note", "s-1"], [2, "noted", "second note", "s-2"]], work(home, "SELECT position, kind, text, session_id FROM work_log ORDER BY position")
  end

  def test_the_printed_rows_of_every_file_land_once_and_the_row_in_knowledge_wins
    home = migrated_home

    assert_equal [["intents/1/plan.md", "aa"], ["intents/2/outcome.md", "bb"], ["refs.md", "dd"], ["shared.md", "knowledge-copy"]], knowledge(home, "SELECT path, sha256 FROM printed ORDER BY path")
  end

  def test_the_files_of_references_that_no_sync_reads_are_printed_back_with_their_bytes_and_leave_sqlar
    home = migrated_home
    printed = %w[1/design.png 1/spec.pdf].map { |name| File.binread(File.join(store_root(home), name)) }

    assert_equal [[[0]], ["\x01\x02\x03".b, "\xFF\x00".b]], [knowledge(home, "SELECT count(*) FROM sqlar"), printed]
  end

  def test_the_retrieval_tables_leave_knowledge
    home = migrated_home
    names = knowledge(home, "SELECT name FROM sqlite_master WHERE type IN ('table', 'trigger')").flatten

    assert_empty names & %w[document_passages document_fts retrieval_schema retrieval_backfills document_heads_search_insert document_heads_search_update document_heads_search_delete changes]
  end

  def test_references_db_is_gone_after_the_commit
    home = migrated_home

    refute_path_exists store_path(home, "references.db")
  end

  def test_a_second_run_changes_nothing
    home = migrated_home
    before = beta_2_files(home).except(*Dir.glob(File.join(store_root(home), "backups", "**", "*")))

    report = migrate(home)

    assert_equal [[], {}], [report.migrated, report.failed]
    assert_equal before, beta_2_files(home).slice(*before.keys)
  end

  def test_after_the_runner_a_search_returns_the_fixture_hit
    home = migrated_home
    hits = Plastic::Graph.open(home:, store: "alpha").retrieval.search("storage")

    assert_equal [["1", "plan.md"]], hits.map { |hit| hit.values_at("intent_id", "path") }
  end

  def test_the_migration_is_backed_up_first_with_the_three_files_of_the_old_store
    home = beta_2_home
    migrate(home)
    folder = Dir.glob(File.join(store_root(home), "backups", "*")).first

    assert_equal %w[knowledge_graph references work_graph], Dir.children(folder).grep(/\.db\z/).map { |name| name.sub(/-\d{14}\.db\z/, "") }.sort
  end
end

class PartialStoreMigrationTest < Plastic::TestCase
  include StoreMigrationRuns

  ABSENT_BETA_2_TABLES = %w[approvals verdicts archives archive_entries clusters completions printed changes savepoints].freeze

  def test_a_store_without_references_db_migrates
    home = beta_2_home(references: false)
    report = migrate(home)

    assert_equal [["alpha"], 0, 2], [report.migrated, knowledge(home, "SELECT count(*) FROM sqlar").flatten.first, knowledge(home, "SELECT count(*) FROM intents").flatten.first]
    refute_path_exists store_path(home, "references.db")
  end

  def test_a_store_that_lacks_one_beta_2_work_table_still_migrates
    migrated = ABSENT_BETA_2_TABLES.to_h do |table|
      home = beta_2_home
      read_file(store_path(home, "work_graph.db"), %(DROP TABLE "#{table}"), readonly: false)
      [table, migrate(home).migrated]
    end

    assert_equal ABSENT_BETA_2_TABLES.to_h { |table| [table, ["alpha"]] }, migrated
  end

  def test_a_store_without_a_knowledge_file_migrates_and_keeps_its_work_rows
    home = beta_2_home
    File.delete(store_path(home, "knowledge_graph.db"), store_path(home, "references.db"))
    report = migrate(home)

    assert_equal [["alpha"], {}], [report.migrated, report.failed]
    assert_equal [[2]], knowledge(home, "SELECT count(*) FROM intents")
    assert_equal fresh_layouts, layouts_of(store_root(home))
  end
end

class StoreMigrationFailureTest < Plastic::TestCase
  include Beta2Store
  include SchemaVersions

  Runner = Plastic::Graph::SchemaRunner
  NOW = Time.utc(2026, 1, 1)
  SQLAR = 'CREATE TABLE "sqlar"("name" TEXT PRIMARY KEY, "mode" INT, "mtime" INT, "sz" INT, "data" BLOB, "intent_id" TEXT, "sha256" TEXT, "origin_id" TEXT NOT NULL, UNIQUE("name"))'

  def plant(home, trigger)
    database = SQLite3::Database.new(store_path(home, "knowledge_graph.db"))
    database.execute(SQLAR)
    database.execute(trigger)
    database.close
  end

  def refusing_copy = 'CREATE TRIGGER refuse BEFORE INSERT ON sqlar BEGIN SELECT RAISE(ABORT, "the copy is refused"); END'

  def rewriting_copy = %(CREATE TRIGGER rewrite AFTER INSERT ON sqlar BEGIN UPDATE sqlar SET sha256 = 'changed' WHERE name = NEW.name; END)

  def state(home) = layouts_of(store_root(home)).merge("recorded" => %w[knowledge_graph work_graph].map { |name| recorded_versions(store_path(home, "#{name}.db")) })

  def rows_digest(home)
    %w[work_graph knowledge_graph].map { |name| read_file(store_path(home, "#{name}.db"), "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name") }
  end

  def failing_run(trigger)
    home = beta_2_home
    plant(home, trigger)
    before = [state(home), rows_digest(home)]
    report = Runner.new(home:, now: NOW, selection: StoreMigrationRuns::SELECTION, released: Plastic::Graph::MIGRATIONS.held(:store)).call
    [home, before, report]
  end

  def test_a_failure_in_the_copy_of_the_kept_files_records_no_version_and_keeps_every_table_and_references_db
    home, before, report = failing_run(refusing_copy)

    assert_equal ["alpha"], report.failed.keys
    assert_equal before, [state(home), rows_digest(home)]
    assert_path_exists store_path(home, "references.db")
  end

  def test_a_mismatched_check_rolls_back_and_keeps_references_db
    home, before, report = failing_run(rewriting_copy)

    assert_includes report.failed.fetch("alpha"), "references.db rows missing from knowledge"
    assert_equal before, [state(home), rows_digest(home)]
    assert_path_exists store_path(home, "references.db")
  end

  def test_an_older_store_is_refused_before_anything_is_written
    home = beta_2_home(older: true)
    before = beta_2_files(home)

    error = assert_raises(Plastic::Graph::OutOfStep) { Runner.new(home:, now: NOW, selection: StoreMigrationRuns::SELECTION, released: Plastic::Graph::MIGRATIONS.held(:store)).call }

    assert_includes error.message, "beta.2"
    assert_equal before, beta_2_files(home)
  end

  def test_an_older_store_refused_by_the_update_command_exits_3
    home = beta_2_home(older: true)
    result = plastic("update", env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE)

    assert_equal 3, result.code
  end
end

class AlphaStoreMigrationTest < Plastic::TestCase
  include StoreMigrationRuns

  # A store an alpha build wrote: the newest layout, stamped 1, with no schema_migrations table.
  def alpha_home
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")
    Plastic::Graph::Database::ConnectionPool.release(store_root(home))
    Plastic::Graph::Database::ConnectionPool.created.clear
    SQLite3::Database.open(store_path(home, "knowledge_graph.db")) { |db| db.execute_batch("DROP TABLE schema_migrations; PRAGMA user_version = 1") }
    home
  end

  def without_versions(home) = layouts_of(store_root(home)).transform_values { |tables| tables.except("schema_migrations") }

  def test_an_alpha_store_at_stamp_1_records_every_version_and_keeps_its_layout
    home = alpha_home
    before = without_versions(home)
    report = migrate(home)

    assert_equal [["alpha"], Plastic::Graph::MIGRATIONS.versions(:store)], [report.migrated, recorded_versions(store_path(home, "knowledge_graph.db"))]
    assert_equal before, without_versions(home)
  end
end

module PreviousReleaseStore
  include StoreMigrationRuns

  DROP = "20261119000000"
  REVISIONS = <<~SQL
    CREATE TABLE document_revisions("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "body" TEXT NOT NULL,
      "created_at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "origin_id"));
    INSERT INTO document_revisions VALUES ('sha', '1', 'intent.md', 'old text', 'then', 'origin');
  SQL

  # A store the previous release wrote: every version before the drop, and a document_revisions table with a row. Its files
  # were made by an earlier process, so this one forgets that it made them.
  def previous_home
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")
    Plastic::Graph::Database::ConnectionPool.release(store_root(home))
    Plastic::Graph::Database::ConnectionPool.created.clear
    SQLite3::Database.open(store_path(home, "knowledge_graph.db")) do |database|
      database.execute_batch(REVISIONS)
      database.execute("DELETE FROM schema_migrations WHERE version = ?", [DROP])
    end
    home
  end

  def keep(home, name, data)
    SQLite3::Database.open(store_path(home, "knowledge_graph.db")) do |database|
      database.execute("INSERT INTO sqlar (name, mode, mtime, sz, data, origin_id) VALUES (?, 420, 0, 0, ?, 'o')", [name, SQLite3::Blob.new(data)])
    end
  end
end

class PreviousStoreMigrationTest < Plastic::TestCase
  include PreviousReleaseStore

  def test_a_store_of_the_previous_release_loses_document_revisions_and_matches_a_new_store
    home = previous_home
    migrate(home)

    assert_equal [[], fresh_layouts], [knowledge(home, "SELECT name FROM sqlite_master WHERE name = 'document_revisions'"), layouts_of(store_root(home))]
  end

  def test_a_store_of_the_previous_release_records_the_drop
    home = previous_home
    migrate(home)

    assert_includes recorded_versions(store_path(home, "knowledge_graph.db")), DROP
  end

  def test_a_store_of_the_previous_release_prints_back_a_file_only_its_kept_row_held_and_removes_the_row
    home = previous_home
    keep(home, "originals/roadmaps/plan.md", "old roadmap")
    migrate(home)

    assert_equal ["old roadmap", [[0]]], [File.read(File.join(store_root(home), "originals/roadmaps/plan.md")), knowledge(home, "SELECT count(*) FROM sqlar")]
  end

  def test_a_store_that_keeps_a_row_with_no_verified_copy_reports_it_on_one_line
    home = previous_home
    name = "store/1--alpha/resources/tmp/scratch.md"
    keep(home, name, "old scratch")
    FileUtils.mkdir_p(File.dirname(File.join(store_root(home), name)))
    File.write(File.join(store_root(home), name), "new scratch")
    report = migrate(home)

    assert_equal [["alpha"], ["migrate: alpha keeps these rows in sqlar, as no verified copy of them is elsewhere: #{name} (the file on disk differs)"]], [report.migrated, report.notes]
  end

  def test_a_store_whose_cleanup_is_refused_stays_behind_with_its_table_and_its_rows
    home = previous_home
    keep(home, "../outside.md", "outside")
    report = migrate(home)

    assert_equal ["it could not be migrated (the kept file ../outside.md leads outside the store folder)", [["document_revisions"]], [[1]]],
      [report.failed.fetch("alpha"), knowledge(home, "SELECT name FROM sqlite_master WHERE name = 'document_revisions'"), knowledge(home, "SELECT count(*) FROM sqlar")]
  end
end

class PreviousStoreLegacyKeepTest < Plastic::TestCase
  include PreviousReleaseStore

  def legacy_file(home) = store_path(home, "legacy.db")

  def legacy(home, sql) = read_file(legacy_file(home), sql)

  def test_a_store_of_the_previous_release_keeps_every_row_of_document_revisions_in_legacy_db_in_its_old_shape
    home = previous_home
    before = knowledge(home, "SELECT * FROM document_revisions")
    shape = knowledge(home, "SELECT name, type, \"notnull\", pk FROM pragma_table_info('document_revisions')")
    migrate(home)

    assert_equal [before, shape], [legacy(home, "SELECT * FROM document_revisions_#{DROP}"), legacy(home, "SELECT name, type, \"notnull\", pk FROM pragma_table_info('document_revisions_#{DROP}')")]
  end

  def test_a_store_of_the_previous_release_keeps_no_sqlar_row_in_legacy_db
    home = previous_home
    keep(home, "originals/roadmaps/plan.md", "old roadmap")
    migrate(home)

    assert_equal [[["document_revisions_#{DROP}"]], "old roadmap"],
      [legacy(home, "SELECT name FROM sqlite_master WHERE type = \x27table\x27"), File.read(File.join(store_root(home), "originals/roadmaps/plan.md"))]
  end

  def revise(home, *row)
    SQLite3::Database.open(store_path(home, "knowledge_graph.db")) { |database| database.execute("INSERT INTO document_revisions VALUES (?, ?, ?, ?, ?, ?)", row) }
  end

  def head(home, path, sha)
    SQLite3::Database.open(store_path(home, "knowledge_graph.db")) do |database|
      database.execute("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES (\x271\x27, ?, \x27text\x27, \x27now\x27, \x27origin\x27)", [path])
      database.execute("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES (\x271\x27, ?, ?, \x27now\x27, \x27origin\x27)", [path, sha])
    end
  end

  def test_a_store_of_the_previous_release_keeps_only_the_earlier_revision_texts_of_the_paths_the_sync_reads
    home = previous_home
    revise(home, "cur", "1", "intent.md", "text", "now", "origin")
    revise(home, "tmp", "1", "resources/tmp/x.md", "scratch", "now", "origin")
    revise(home, "road", "", "roadmaps/plan.md", "plan", "now", "origin")
    head(home, "intent.md", "cur")
    migrate(home)

    assert_equal [["road"], ["sha"]], legacy(home, "SELECT sha256 FROM document_revisions_#{DROP} ORDER BY sha256")
  end

  def test_a_store_whose_cleanup_is_refused_makes_no_legacy_db
    home = previous_home
    keep(home, "../outside.md", "outside")
    migrate(home)

    refute_path_exists legacy_file(home)
  end

  def test_a_store_whose_legacy_db_cannot_be_made_stays_behind_with_its_table
    home = previous_home
    FileUtils.mkdir_p(legacy_file(home))
    report = migrate(home)

    assert_equal [false, [["document_revisions"]]], [report.migrated.include?("alpha"), knowledge(home, "SELECT name FROM sqlite_master WHERE name = 'document_revisions'")]
  end

  def test_a_current_store_makes_no_legacy_db
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")
    migrate(home)

    refute_path_exists legacy_file(home)
  end
end

class StoreMigrationCompactionTest < Plastic::TestCase
  include StoreMigrationRuns

  FILES = %w[knowledge_graph.db work_graph.db retrieval_graph.db].freeze
  FULL_DISK = ->(_home, _slug) { raise SQLite3::FullException, "database or disk is full" }
  FAILED = "compact: alpha was not compacted (database or disk is full); run plastic update to try again"

  def migration(home, compaction: Plastic::Graph::StoreCompaction) = Plastic::Graph::StoreMigration.new(home, "alpha", NOW, run: Plastic::Graph::StoreMigration::Run.new(selection: SELECTION, released: Plastic::Graph::MIGRATIONS.held(:store)), compaction:)

  def vacuum_modes(home) = FILES.map { |name| SQLite3::Database.open(store_path(home, name)) { |database| database.get_first_value("PRAGMA auto_vacuum") } }

  def current_home
    home = File.join(Dir.mktmpdir, ".plastic")
    Plastic::Graph.create(home:, store: "alpha")
    Plastic::Graph::Database::ConnectionPool.release(store_root(home))
    home
  end

  def without_vacuum(home)
    FILES.each { |name| SQLite3::Database.open(store_path(home, name)) { |database| database.execute_batch("PRAGMA auto_vacuum = NONE; VACUUM") } }
    home
  end

  def test_a_compaction_that_fails_after_the_commit_reports_a_failed_compaction_and_the_store_as_migrated
    home = beta_2_home
    File.delete(store_path(home, "knowledge_graph.db"), store_path(home, "references.db"))
    run = migration(home, compaction: FULL_DISK)

    assert_equal [:migrated, [FAILED]], [run.call, run.notes]
    assert_equal [[2]], knowledge(home, "SELECT count(*) FROM intents")
  end

  def test_a_current_store_with_a_file_not_on_incremental_vacuum_is_compacted
    home = without_vacuum(current_home)

    assert_equal [:current, [2, 2, 2]], [migration(home).call, vacuum_modes(home)]
  end

  def test_a_failed_compaction_is_tried_again_by_the_next_run
    home = beta_2_home
    migration(home, compaction: FULL_DISK).call
    migration(home).call

    assert_equal [2, 2, 2], vacuum_modes(home)
  end

  def test_a_current_store_whose_files_are_all_on_incremental_vacuum_is_not_compacted
    calls = []
    migration(current_home, compaction: ->(_home, slug) { calls << slug }).call

    assert_empty calls
  end

  def test_a_current_store_whose_compaction_fails_stays_current_and_reports_it
    run = migration(without_vacuum(current_home), compaction: FULL_DISK)

    assert_equal [:current, [FAILED]], [run.call, run.notes]
  end
end

class StoreMigrationCreatedFilesTest < Plastic::TestCase
  include PreviousStore

  Pool = Plastic::Graph::Database::ConnectionPool

  def teardown
    Pool.created.clear
    super
  end

  def migrate(home) = Plastic::Graph::SchemaRunner.new(home:, now: MIGRATED_AT, selection: Plastic::Graph::Knowledge::SyncSelection.none, released: [DROP]).call

  def test_after_a_migration_commits_a_later_removal_of_the_files_the_process_made_keeps_legacy_db
    home = previous_home
    Pool.created.clear
    migrate(home)
    Pool.release(home)
    Pool.remove_created(alpha_file(home, ""))

    assert_equal [false, ["document_revisions_#{DROP}"]], [Pool.created.include?(File.expand_path(alpha_file(home, "legacy.db"))), legacy_tables(home)]
  end
end

class StoreMigrationLegacyRollbackTest < Plastic::TestCase
  include PreviousStore

  LATER = <<~SQL
    DELETE FROM schema_migrations WHERE version = '#{PreviousStore::DROP}';
    CREATE TABLE document_revisions("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "body" TEXT NOT NULL, "created_at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "intent_id", "path", "origin_id"));
    INSERT INTO document_revisions VALUES ('sha2', '1', 'intent.md', 'new text', 'now', 'origin');
    INSERT INTO sqlar (name, mode, mtime, sz, data, origin_id) VALUES ('originals/roadmaps/later.md', 420, 0, 0, CAST('later roadmap' AS BLOB), 'o');
    CREATE TRIGGER refuse_delete BEFORE DELETE ON sqlar BEGIN SELECT RAISE(ABORT, 'refused'); END;
  SQL

  # A store whose legacy.db holds the rows of a first run, put back before the drop with new rows, and a cleanup that fails.
  def failing_second_run
    home = migrated_previous_home
    SQLite3::Database.open(alpha_file(home, "knowledge_graph.db")) { |database| database.execute_batch(LATER) }
    [home, migrate_store(home)]
  end

  def test_a_failed_run_into_a_legacy_db_that_holds_rows_leaves_only_the_old_rows_and_the_store_behind
    home, report = failing_second_run

    assert_equal ["it could not be migrated (refused)", [["sha"]], [["sha2"]], false],
      [report.failed.fetch("alpha"), alpha_rows(home, "legacy.db", "SELECT sha256 FROM document_revisions_#{DROP}"),
        alpha_rows(home, "knowledge_graph.db", "SELECT sha256 FROM document_revisions"), recorded(home).include?(DROP)]
  end
end

class StoreMigrationSwitchTest < Plastic::TestCase
  include PreviousStore

  def migrate(home, released) = Plastic::Graph::SchemaRunner.new(home:, now: MIGRATED_AT, selection: Plastic::Graph::Knowledge::SyncSelection.none, released:).call.tap { forget(home) }

  def revisions_table(home) = alpha_rows(home, "knowledge_graph.db", "SELECT name FROM sqlite_master WHERE name = 'document_revisions'").flatten

  def test_while_the_switch_is_off_a_store_runs_only_the_report_migration_keeps_its_table_and_makes_no_legacy_db
    home = previous_home
    report = migrate(home, [])

    assert_equal [["alpha"], false, ["document_revisions"], false], [report.migrated, recorded(home).include?(DROP), revisions_table(home), File.exist?(alpha_file(home, "legacy.db"))]
  end

  def test_once_the_switch_is_on_the_store_runs_the_drop_and_keeps_the_table_in_legacy_db
    home = previous_home
    report = migrate(home, [DROP])

    assert_equal [["alpha"], true, [], ["document_revisions_#{DROP}"]], [report.migrated, recorded(home).include?(DROP), revisions_table(home), legacy_tables(home)]
  end
end

class ReportRowsMigrationTest < Plastic::TestCase
  include PreviousStore

  Knowledge = Plastic::Graph::Knowledge
  DIR = "store/1--alpha"
  LOOSE = "resources/output/reports/loose.html"
  MANDATORY = "resources/output/reports/summary.md"
  FILES = { "spec.md" => "# Spec\n", LOOSE => "<p>loose</p>\n", MANDATORY => "# Summary\n", "resources/output/files/data.html" => "<p>data</p>\n" }.freeze

  def selection = Knowledge::SyncSelection.new(types: %w[md html], references: false, asked: [], reports: Knowledge::Reports.new(mandatory: %w[summary.md]))

  def migrate(home) = Plastic::Graph::SchemaRunner.new(home:, now: MIGRATED_AT, selection:, released: [DROP]).call.tap { forget(home) }

  # A store the previous release synced: every report read into rows, as the sync read them by type.
  def synced_home
    home = previous_home
    FILES.each { |rel, text| write_file(home, rel, text) }
    knowledge_rows(home)
    open_alpha(home, "retrieval_graph.db") do |database|
      FILES.each_key { |rel| database.execute("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES ('b', '1', ?, 's', 0, 'o')", [rel]) }
    end
    home
  end

  def write_file(home, rel, text)
    path = File.join(alpha_file(home, ""), DIR, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def knowledge_rows(home)
    open_alpha(home, "knowledge_graph.db") do |database|
      database.execute("INSERT INTO intents (intent_id, origin_id, slug, title, status) VALUES ('1', 'o', 'alpha', 'Alpha', 'open')")
      FILES.each { |rel, text| document_rows(database, rel, text) }
    end
  end

  def document_rows(database, rel, text)
    database.execute("INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES ('1', ?, ?, 'then', 'o')", [rel, text])
    database.execute("INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES ('1', ?, ?, 'then', 'o')", [rel, Digest::SHA256.hexdigest(text)])
    database.execute("INSERT INTO printed (path, sha256, at, origin_id) VALUES (?, 's', 'then', 'o')", ["#{DIR}/#{rel}"])
  end

  def open_alpha(home, name, &) = SQLite3::Database.open(alpha_file(home, name), &)

  def paths(name, sql) = alpha_rows(@home, name, sql).flatten.sort

  def test_the_report_migration_drops_the_rows_of_every_report_that_is_not_mandatory
    @home = synced_home
    migrate(@home)

    kept = [LOOSE, MANDATORY, "resources/output/files/data.html", "spec.md"] - [LOOSE]

    assert_equal [kept.sort, kept.sort, kept.map { |rel| "#{DIR}/#{rel}" }.sort, kept.sort],
      [paths("knowledge_graph.db", "SELECT path FROM documents"), paths("knowledge_graph.db", "SELECT path FROM document_heads"),
        paths("knowledge_graph.db", "SELECT path FROM printed WHERE path LIKE \x27store/%\x27"), paths("retrieval_graph.db", "SELECT path FROM document_fts")]
  end

  def test_the_report_migration_keeps_the_rows_of_a_recorded_report
    @home = synced_home
    open_alpha(@home, "work_graph.db") do |database|
      database.execute("INSERT INTO work_log (intent_id, position, kind, path, origin_id) VALUES ('1', 1, 'reported', ?, 'other')", [LOOSE])
    end
    migrate(@home)

    assert_includes paths("knowledge_graph.db", "SELECT path FROM documents"), LOOSE
  end

  def test_the_report_migration_leaves_the_files_on_disk
    @home = synced_home
    migrate(@home)

    assert File.file?(File.join(alpha_file(@home, ""), DIR, LOOSE))
  end

  def test_the_report_migration_is_recorded_and_keeps_nothing_in_legacy_db
    @home = synced_home
    migrate(@home)

    assert_equal [true, ["document_revisions_#{DROP}"]], [recorded(@home).include?(REPORTS), legacy_tables(@home)]
  end
end
