# frozen_string_literal: true

require_relative "../support/kernel"

class ChangeLogTest < Minitest::Test
  include KernelFixtures::StoreCalls

  def work = @work ||= store_graphs.databases[:work]

  def origin = Plastic::Graph::Origin.new(@plastic_home).id

  def changes(database = work) = database.rows("SELECT * FROM changes ORDER BY seq")

  def test_every_put_appends_one_change_with_the_whole_row
    work.transaction { |batch| batch.put(:clusters, { name: "Core", intent_id: "1" }) }
    change = sole(changes)

    assert_equal ["clusters", "put", origin], change.values_at("table", "operation", "origin_id")
    assert_equal({ "name" => "Core", "intent_id" => "1", "origin_id" => origin }, JSON.parse(change["row"]))
    assert_match(/[+-]\d\d:\d\d\z/, change["at"])
  end

  def test_the_change_row_carries_the_autoincrement_id
    store_graphs.work.write_intent(title: "Alpha")
    row = JSON.parse(changes.find { |change| change["table"] == "intents" }["row"])

    assert_equal 1, row["id"]
    assert_equal "1", row["intent_id"]
  end

  def test_a_failed_write_leaves_no_change_row
    assert_raises(Plastic::Graph::Database::Error) do
      work.transaction do |batch|
        batch.put(:clusters, { name: "Core", intent_id: "1" })
        batch.add("INSERT INTO nowhere VALUES (1)")
      end
    end

    assert_empty changes
    assert_empty work.rows("SELECT * FROM clusters")
  end

  def test_a_removal_is_logged_with_no_row
    work.transaction { |batch| batch.put(:clusters, { name: "Core", intent_id: "1" }) }
    work.transaction { |batch| batch.remove(:clusters, name: "Core") }
    change = changes.last

    assert_equal "remove", change["operation"]
    assert_nil change["row"]
    assert_equal({ "name" => "Core", "intent_id" => "1", "origin_id" => origin }, JSON.parse(change["key"]))
  end

  def test_a_kept_file_logs_its_bytes_as_hex
    references = store_graphs.databases[:references]
    row = { name: "store/1--a/resources/x.bin", mode: 0o100644, mtime: 0, sz: 2, data: Plastic::Graph::SQL::Bytes.new("ab"),
            intent_id: "1", sha256: "x" }
    references.transaction { |batch| batch.put(:sqlar, row) }

    assert_equal "6162", JSON.parse(sole(changes(references))["row"])["data"]
  end

  def test_the_home_database_keeps_no_change_log
    home = store_graphs.databases[:home]
    home.transaction { |batch| batch.put(:routine_runs, { store: "global", tool: "x", subject: "" }) }

    assert_empty home.rows("SELECT name FROM sqlite_master WHERE name = 'changes'")
  end
end
