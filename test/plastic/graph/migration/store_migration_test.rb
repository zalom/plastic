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

  def migrate(home) = Runner.new(home:, now: NOW, selection: SELECTION).call

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
    report = Runner.new(home:, now: NOW, selection: StoreMigrationRuns::SELECTION).call
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

    error = assert_raises(Plastic::Graph::OutOfStep) { Runner.new(home:, now: NOW, selection: StoreMigrationRuns::SELECTION).call }

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

class PreviousStoreMigrationTest < Plastic::TestCase
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

  def keep(home, name, data)
    SQLite3::Database.open(store_path(home, "knowledge_graph.db")) do |database|
      database.execute("INSERT INTO sqlar (name, mode, mtime, sz, data, origin_id) VALUES (?, 420, 0, 0, ?, 'o')", [name, SQLite3::Blob.new(data)])
    end
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

  def legacy_file(home) = store_path(home, "legacy.db")

  def legacy(home, sql) = read_file(legacy_file(home), sql)

  def test_a_store_of_the_previous_release_keeps_every_row_of_document_revisions_in_legacy_db_in_its_old_shape
    home = previous_home
    before = knowledge(home, "SELECT * FROM document_revisions")
    shape = knowledge(home, "SELECT name, type, \"notnull\", pk FROM pragma_table_info('document_revisions')")
    migrate(home)

    assert_equal [before, shape], [legacy(home, "SELECT * FROM document_revisions_#{DROP}"), legacy(home, "SELECT name, type, \"notnull\", pk FROM pragma_table_info('document_revisions_#{DROP}')")]
  end

  def test_a_store_of_the_previous_release_keeps_each_removed_sqlar_row_with_its_bytes_and_no_row_it_keeps
    home = previous_home
    keep(home, "originals/roadmaps/plan.md", "old roadmap")
    keep(home, "store/1--alpha/resources/tmp/scratch.md", "old scratch")
    File.join(store_root(home), "store/1--alpha/resources/tmp/scratch.md").then { |path| FileUtils.mkdir_p(File.dirname(path)).then { File.write(path, "new scratch") } }
    migrate(home)

    assert_equal [[["originals/roadmaps/plan.md", "old roadmap"]], [["store/1--alpha/resources/tmp/scratch.md"]]],
      [legacy(home, "SELECT name, data FROM sqlar_#{DROP}"), knowledge(home, "SELECT name FROM sqlar")]
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

  def test_after_a_migration_commits_a_later_removal_of_the_files_the_process_made_keeps_legacy_db
    home = previous_home
    Plastic::Graph::Database::ConnectionPool.created.clear
    migrate(home)
    Plastic::Graph::Database::ConnectionPool.release(store_root(home))
    Plastic::Graph::Database::ConnectionPool.remove_created(File.join(store_root(home), ""))

    assert_equal [false, ["document_revisions_#{DROP}", "sqlar_#{DROP}"]],
      [Plastic::Graph::Database::ConnectionPool.created.include?(File.expand_path(legacy_file(home))), legacy(home, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").flatten]
  ensure
    Plastic::Graph::Database::ConnectionPool.created.clear
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

  def migration(home, compaction: Plastic::Graph::StoreCompaction) = Plastic::Graph::StoreMigration.new(home, "alpha", NOW, selection: SELECTION, compaction:)

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
