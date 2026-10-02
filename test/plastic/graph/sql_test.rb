# frozen_string_literal: true

require_relative "../../test_helper"

class SQLTest < Plastic::TestCase
  SQL = Plastic::Graph::SQL

  def test_literals_quote_every_kind_of_value
    values = [nil, true, false, 3, 1.5, SQL::Bytes.new("ab"), SQL::Raw.new("retries + 1"), { "a" => 1 }, [1], "it's", :sym]

    assert_equal ["NULL", "1", "0", "3", "1.5", "X'6162'", "retries + 1", %('{"a":1}'), "'[1]'", "'it''s'", "'sym'"],
      values.map { |value| SQL.literal(value) }
  end

  def test_a_name_is_quoted
    assert_equal %("say ""hi"""), SQL.name(%(say "hi"))
  end

  def test_bind_fills_known_names_only
    assert_equal "SELECT 'a' WHERE b = :b AND c::text", SQL.bind("SELECT :a WHERE b = :b AND c::text", a: "a")
  end

  def test_bind_with_no_values_leaves_the_sql
    assert_equal "SELECT :a", SQL.bind("SELECT :a", {})
  end

  def test_names_join_quoted_names
    assert_equal %("a", "b"), SQL.names(%i[a b])
  end

  def test_an_assignment_takes_the_excluded_value
    assert_equal %("a" = excluded."a"), SQL.assignment(:a)
  end

  def test_where_matches_each_value_with_is
    assert_equal %("a" IS 1 AND "b" IS NULL), SQL.where({ a: 1, b: nil })
  end

  def test_a_tuple_lists_columns_then_values
    assert_equal %(("a", "b") VALUES (1, 'x')), SQL.tuple({ a: 1, b: "x" })
  end
end
