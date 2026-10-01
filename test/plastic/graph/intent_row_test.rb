# frozen_string_literal: true

require_relative "../../test_helper"

class IntentRowTest < Plastic::TestCase
  COLUMNS = %w[id intent_id parent_id ref origin_id slug title kind status disposition opened_at closed_at updated_at].freeze

  def work = @work ||= store_graphs.databases[:work]

  def test_the_intent_table_has_the_ruled_columns
    assert_equal COLUMNS, work.rows("SELECT name FROM pragma_table_info('intents')").map { |row| row["name"] }
  end

  def test_the_six_statuses_are_the_ruled_ones
    assert_equal %w[open active parked future done abandoned], Plastic::Graph::Intent::STATUSES
  end

  def test_a_status_outside_the_six_is_refused
    error = assert_raises(Plastic::Graph::Database::Error) do
      work.transaction { |batch| batch.put(:intents, { intent_id: "1", slug: "a", title: "A", status: "later" }) }
    end

    assert_match(/CHECK constraint failed/, error.message)
  end

  def test_the_same_intent_id_from_two_origins_is_two_rows
    work.transaction do |batch|
      batch.put(:intents, { intent_id: "1", origin_id: "aaaa", slug: "a", title: "A", status: "open" })
      batch.put(:intents, { intent_id: "1", origin_id: "bbbb", slug: "a", title: "A", status: "open" })
    end

    assert_equal [1, 2], work.rows("SELECT id FROM intents ORDER BY id").map { |row| row["id"] }
  end

  def test_a_second_put_keeps_the_id
    2.times { |n| work.transaction { |batch| batch.put(:intents, { intent_id: "1", slug: "a", title: "A#{n}", status: "open" }) } }

    assert_equal [{ "id" => 1, "title" => "A1" }], work.rows("SELECT id, title FROM intents")
  end
end
