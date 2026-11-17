# frozen_string_literal: true

require "digest"
require "sqlite3"
require_relative "../../../../test_helper"

# Store migration 1 is frozen: its text is pinned by a digest, and the rebuilds
# of older tables are proven on real databases.
class SchemaStore1PinTest < Plastic::TestCase
  # The SHA-256 of the texts of store migration 1. An edit to a landed migration fails this test; a
  # change to the schema is a later migration, never an edit of this one.
  PINNED = "bba301bf3d46e239527efac652486694c022e714fe2455287362812de19a0029"

  def test_the_text_of_the_landed_migration_is_pinned_by_its_digest
    assert_equal PINNED, Digest::SHA256.hexdigest(Plastic::Graph::SchemaStore1.texts.join("\n--\n"))
  end

  def test_the_pin_changes_when_one_character_of_the_text_changes
    texts = Plastic::Graph::SchemaStore1.texts
    edited = [texts.first.sub("CREATE", "CREATED"), *texts.drop(1)]

    refute_equal PINNED, Digest::SHA256.hexdigest(edited.join("\n--\n"))
  end

  def test_the_migration_never_reads_the_live_schema
    source = File.read(File.join(__dir__, "../../../../../lib/plastic/graph/schema/sequences/store_1.rb"))

    refute_match(/Schema\.(fetch|ddl|prepare)/, source)
  end
end

class SchemaStore1IntentsTest < Plastic::TestCase
  Sequences = Plastic::Graph::SchemaSequences

  OLD_INTENTS = <<~SQL
    CREATE TABLE "intents"("id" INTEGER PRIMARY KEY AUTOINCREMENT, "intent_id" TEXT NOT NULL, "parent_id" TEXT, "ref" TEXT,
      "origin_id" TEXT NOT NULL, "slug" TEXT NOT NULL, "title" TEXT NOT NULL, "kind" TEXT,
      "status" TEXT NOT NULL CHECK(status IN ('open', 'active', 'parked', 'future', 'done', 'abandoned')),
      "disposition" TEXT, "opened_at" TEXT, "closed_at" TEXT, "updated_at" TEXT, UNIQUE("intent_id", "origin_id"));
  SQL

  ROWS = [[1, "active", nil], [2, "done", "shipped on friday"], [3, "abandoned", "superseded by intent 9"],
    [4, "abandoned", "dropped by the owner"], [5, "open", "left over"], [6, "parked", nil], [7, "future", nil]].freeze

  def setup
    super
    @database = SQLite3::Database.new(":memory:")
    @database.execute_batch(OLD_INTENTS)
    ROWS.each do |id, status, disposition|
      @database.execute("INSERT INTO intents (id, intent_id, origin_id, slug, title, status, disposition) VALUES (?, ?, 'o', 's', 't', ?, ?)",
        [id, id.to_s, status, disposition])
    end
  end

  def migrate = Sequences.migrate(@database, Sequences::SEQUENCES.fetch(:store), :work)

  def intents = @database.execute("SELECT id, status, disposition, reason FROM intents ORDER BY id")

  def columns = @database.execute("PRAGMA table_info(intents)").map { |column| column[1] }

  def test_the_old_word_for_work_under_way_becomes_in_progress_and_the_ids_stay
    migrate

    assert_equal [[1, "in_progress"], [2, "done"], [3, "abandoned"], [4, "abandoned"], [5, "open"], [6, "parked"], [7, "future"]],
      intents.map { |id, status| [id, status] }
  end

  def test_the_new_state_passes_the_status_check
    migrate
    @database.execute("INSERT INTO intents (intent_id, origin_id, slug, title, status) VALUES ('9', 'o', 's', 't', 'in_progress')")

    assert_equal "in_progress", @database.get_first_value("SELECT status FROM intents WHERE intent_id = '9'")
  end

  def test_free_text_in_the_disposition_moves_to_the_reason
    migrate

    assert_equal [[2, "delivered", "shipped on friday"], [3, "superseded", "superseded by intent 9"],
      [4, "cancelled", "dropped by the owner"], [5, nil, "left over"], [6, nil, nil]],
      intents.select { |id, _status| id > 1 && id < 7 }.map { |id, _status, disposition, reason| [id, disposition, reason] }
  end

  def test_a_done_intent_without_text_is_delivered
    @database.execute("UPDATE intents SET disposition = NULL WHERE id = 2")
    migrate

    assert_equal ["delivered", nil], @database.get_first_row("SELECT disposition, reason FROM intents WHERE id = 2")
  end

  def test_a_database_without_the_intents_table_gets_the_declared_one
    @database.execute("DROP TABLE intents")
    migrate

    assert_includes columns, "reason"
  end

  def test_the_sequence_of_the_ids_is_kept
    migrate
    @database.execute("INSERT INTO intents (intent_id, origin_id, slug, title, status) VALUES ('9', 'o', 's', 't', 'open')")

    assert_equal 8, @database.get_first_value("SELECT id FROM intents WHERE intent_id = '9'")
  end

  def test_a_table_with_neither_the_old_word_nor_the_reason_is_rebuilt
    @database.execute("DROP TABLE intents")
    @database.execute(OLD_INTENTS.sub("'open', 'active',", "'open', 'in_progress',"))
    migrate

    assert_includes columns, "reason"
  end

  def test_a_second_run_changes_nothing
    migrate
    ddl = @database.get_first_value("SELECT sql FROM sqlite_master WHERE name = 'intents'")
    Plastic::Graph::SchemaStore1.apply(@database, :work)

    assert_equal ddl, @database.get_first_value("SELECT sql FROM sqlite_master WHERE name = 'intents'")
  end

  def test_the_migration_stamps_the_database_with_its_number
    migrate

    assert_equal 1, @database.get_first_value("PRAGMA user_version")
  end
end

class SchemaStore1SearchTest < Plastic::TestCase
  Sequences = Plastic::Graph::SchemaSequences
  Store1 = Plastic::Graph::SchemaStore1

  OLD_PASSAGES = <<~SQL
    CREATE TABLE "document_passages"("sha256" TEXT NOT NULL, "position" INTEGER NOT NULL, "body" TEXT NOT NULL,
      "line_start" INTEGER NOT NULL, "line_end" INTEGER NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "position", "origin_id"));
  SQL

  OLD_REVISIONS = <<~SQL
    CREATE TABLE "document_revisions"("sha256" TEXT NOT NULL, "intent_id" TEXT NOT NULL, "path" TEXT NOT NULL, "body" TEXT NOT NULL,
      "created_at" TEXT NOT NULL, "origin_id" TEXT NOT NULL, UNIQUE("sha256", "origin_id"));
  SQL

  def setup
    super
    @database = SQLite3::Database.new(":memory:")
    @database.execute_batch(Store1::Layout::TEXT.fetch(:knowledge))
    @database.execute_batch("DROP TABLE document_passages; DROP TABLE document_revisions; #{Store1::Swaps::SEARCH_TRIGGER_DROPS} #{OLD_REVISIONS} #{OLD_PASSAGES}")
    @database.execute("INSERT INTO document_revisions VALUES ('aaa', '1', 'plan.md', 'old words', 't', 'o')")
    @database.execute("INSERT INTO document_passages VALUES ('aaa', 0, 'old words', 1, 1, 'o')")
    @database.execute("INSERT INTO document_heads VALUES ('1', 'plan.md', 'aaa', 't', 'o')")
    @database.execute("INSERT INTO document_fts (body, intent_id, path, sha256, position, origin_id) VALUES ('old words', '1', 'plan.md', 'aaa', 0, 'o')")
    Sequences.migrate(@database, Sequences::SEQUENCES.fetch(:store), :knowledge)
  end

  def triggers = @database.execute("SELECT name FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'document_heads'").flatten

  def columns(table) = @database.execute("PRAGMA table_info(#{table})").map { |column| column[1] }

  def test_a_store_with_the_older_passages_table_keeps_its_triggers_after_the_swap
    assert_equal 3, triggers.size
    assert_includes columns("document_passages"), "intent_id"
  end

  def test_the_revisions_table_with_the_older_membership_is_rebuilt_and_keeps_its_row
    sql = @database.get_first_value("SELECT sql FROM sqlite_master WHERE name = 'document_revisions'")

    refute_includes sql, Store1::REVISION_MEMBERSHIP
    assert_equal [["aaa", "old words"]], @database.execute("SELECT sha256, body FROM document_revisions")
  end

  def test_a_store_with_the_older_passages_table_still_finds_its_words
    assert_equal [["old words"]], @database.execute("SELECT body FROM document_fts WHERE document_fts MATCH 'old'")
  end

  def test_the_triggers_work_on_the_table_that_the_swap_made
    @database.execute("INSERT INTO document_passages VALUES ('bbb', '1', 'plan.md', 0, 'new words', 1, 1, 'o')")
    @database.execute("UPDATE document_heads SET sha256 = 'bbb'")

    assert_equal [[], [["new words"]]], [@database.execute("SELECT body FROM document_fts WHERE document_fts MATCH 'old'"), @database.execute("SELECT body FROM document_fts WHERE document_fts MATCH 'new'")]
  end
end
