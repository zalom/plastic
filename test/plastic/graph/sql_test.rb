# frozen_string_literal: true

require_relative "../../test_helper"

class SQLTest < Plastic::TestCase
  SQL = Plastic::Graph::SQL

  def bound(sql, values) = SQL::Bound.new(sql, values)

  def test_convert_gives_each_kind_of_value_what_the_literal_gave
    values = [nil, true, false, 3, 1.5, { "a" => 1 }, [1], "it's", :sym]

    assert_equal [nil, 1, 0, 3, 1.5, %({"a":1}), "[1]", "it's", "sym"], values.map { |value| SQL.convert(value) }
  end

  def test_convert_binds_a_binary_string_as_utf_8_text
    converted = SQL.convert("café".b)

    assert_equal ["café", Encoding::UTF_8], [converted, converted.encoding]
    refute_kind_of SQLite3::Blob, converted
  end

  def test_convert_keeps_a_blob_as_it_is
    blob = SQLite3::Blob.new("\x00\xff".b)

    assert_same blob, SQL.convert(blob)
  end

  def test_a_name_is_quoted
    assert_equal %("say ""hi"""), SQL.name(%(say "hi"))
  end

  def test_placeholders_lists_each_name_once_and_skips_a_cast
    assert_equal %i[a b], SQL.placeholders("SELECT :a, :b, :a WHERE c::text = 'x'")
  end

  def test_params_takes_the_names_of_the_text_and_drops_an_extra_key
    assert_equal({ a: 1, b: "x" }, SQL.params("SELECT :a, :b", a: 1, b: :x, extra: 2))
  end

  def test_params_with_a_missing_value_raises_invalid
    error = assert_raises(Plastic::Invalid) { SQL.params("SELECT :a, :b", a: 1) }

    assert_includes error.message, ":b"
  end

  def test_names_join_quoted_names
    assert_equal %("a", "b"), SQL.names(%i[a b])
  end

  def test_an_assignment_takes_the_excluded_value
    assert_equal %("a" = excluded."a"), SQL.assignment(:a)
  end

  def test_where_matches_each_value_with_is_and_names_each_placeholder_after_the_prefix
    assert_equal bound(%("a" IS :m_a AND "b" IS :m_b), { m_a: 1, m_b: nil }), SQL.where({ a: 1, b: nil }, "m")
  end

  def test_set_assigns_each_value_and_keeps_raw_sql_inline
    set = SQL.set({ state: "open", retries: SQL::Raw.new("retries + 1") }, "s")

    assert_equal bound(%("state" = :s_state, "retries" = retries + 1), { s_state: "open" }), set
  end

  def test_a_tuple_lists_columns_then_placeholders
    assert_equal bound(%(("a", "b") VALUES (:v_a, :v_b)), { v_a: 1, v_b: "x" }), SQL.tuple({ a: 1, b: "x" }, "v")
  end

  def test_a_tuple_refuses_raw_sql_as_a_value
    assert_raises(Plastic::Invalid) { SQL.tuple({ a: SQL::Raw.new("1; DROP TABLE t") }, "v") }
  end

  def test_a_tuple_refuses_a_column_name_that_is_not_a_plain_lowercase_name
    ["A", "a b", "a\"b", "1a", "a); DROP TABLE t; --"].each do |name|
      assert_raises(Plastic::Invalid, name) { SQL.tuple({ name.to_sym => 1 }, "v") }
    end
  end

  def test_a_list_names_each_item_after_the_prefix
    assert_equal bound(":f_0, :f_1, :f_2", { f_0: "a", f_1: "b", f_2: "c" }), SQL.list(%w[a b c], "f")
  end

  def test_a_move_binds_its_states_and_its_values
    move = SQL.move(to: "claimed", from: %w[open failed], set: { by: "x", retries: SQL::Raw.new("retries + 1") })

    assert_equal ["claimed", "x", "open", "failed"], move.values.values_at(:s_state, :s_by, :f_0, :f_1)
    assert_includes move.sql, %("state" = :s_state, "updated_at" = :s_updated_at, "by" = :s_by, "retries" = retries + 1)
    assert_includes move.sql, "AND state IN (:f_0, :f_1)\nRETURNING id"
  end

  def test_the_bind_and_the_literal_are_gone
    refute_respond_to SQL, :bind
    refute_respond_to SQL, :literal
  end
end
