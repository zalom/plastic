# frozen_string_literal: true

require_relative "../../../test_helper"

class AttachedStoreTest < Plastic::TestCase
  Database = Plastic::Graph::Database
  Pool = Database::ConnectionPool

  def root = File.join(@home, "attached", "store")

  def origin = Plastic::Graph::Origin.new(@plastic_home)

  def store = (@store ||= Database.open_store(root, origin))

  def connection = Pool.for(store.path, attach: store.files)

  def schemas = connection.execute("PRAGMA database_list").to_h { |row| [row["name"], File.basename(row["file"])] }

  def test_a_store_is_one_database_with_work_and_retrieval_attached_to_knowledge
    store.rows("SELECT 1")

    assert_equal({ "main" => "knowledge_graph.db", "work" => "work_graph.db", "retrieval" => "retrieval_graph.db" }, schemas)
  end

  def test_every_schema_keeps_a_delete_journal_and_full_synchronous
    store.rows("SELECT 1")

    %w[main work retrieval].each do |schema|
      assert_equal ["delete", 2], [connection.get_first_value("PRAGMA #{schema}.journal_mode"), connection.get_first_value("PRAGMA #{schema}.synchronous")]
    end
  end

  def test_a_file_in_another_journal_mode_is_refused_by_name
    FileUtils.mkdir_p(root)
    SQLite3::Database.new(File.join(root, "work_graph.db")) { |database| database.execute("PRAGMA journal_mode = WAL") }

    error = assert_raises(Database::JournalModeRefused) { store.rows("SELECT 1") }

    assert_match(/work_graph\.db.*wal/, error.message)
  end

  def test_plain_sql_reaches_a_table_of_each_file_without_a_prefix
    store.rows("SELECT 1")

    assert_equal [0, 0, 0], ["nodes", "intents", "document_passages"].map { |table| store.rows("SELECT COUNT(*) AS n FROM #{table}").first.fetch("n") }
  end

  def names_in(schema) = connection.execute("SELECT name FROM #{schema}.sqlite_master WHERE type = 'table'").map { |row| row["name"] }

  def test_each_table_is_built_in_the_file_that_owns_it
    store.rows("SELECT 1")

    assert_equal [true, true, true], [names_in("work").include?("nodes"), names_in("main").include?("intents"), names_in("retrieval").include?("document_passages")]
  end

  def test_a_table_is_not_built_in_a_file_that_does_not_own_it
    store.rows("SELECT 1")

    refute_includes names_in("work"), "intents"
  end

  def test_printed_lives_in_main_only_and_no_file_keeps_a_changes_table
    store.rows("SELECT 1")
    count = ->(schema, table) { connection.get_first_value("SELECT COUNT(*) FROM #{schema}.sqlite_master WHERE name = '#{table}'") }

    assert_equal [1, 0, 0], %w[main work retrieval].map { |schema| count.call(schema, "printed") }
    assert_equal [0, 0, 0], %w[main work retrieval].map { |schema| count.call(schema, "changes") }
  end

  def test_a_write_to_work_and_knowledge_lands_together_or_not_at_all
    assert_raises(Database::Error) do
      store.transaction do |batch|
        batch.put(:clusters, { name: "Core", intent_id: "1" })
        batch.add("INSERT INTO nodes(intent_id, id) VALUES ('1', 'n1')")
        batch.add("INSERT INTO nowhere VALUES (1)")
      end
    end

    assert_equal [0, 0], [store.rows("SELECT * FROM clusters").size, store.rows("SELECT * FROM nodes").size]
  end

  def test_the_phrases_name_each_file_that_a_call_wrote_in_order
    store.transaction do |batch|
      batch.put(:clusters, { name: "Core", intent_id: "1" })
      batch.put(:work_log, { intent_id: "1", position: 1, at: "2026-11-23T00:00:00+01:00", kind: "noted", text: "t" })
    end

    assert_equal ["1 work log line in work_graph.db", "1 cluster in knowledge_graph.db"], store.phrases
  end
end
