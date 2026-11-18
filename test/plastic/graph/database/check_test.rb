# frozen_string_literal: true

require_relative "../../../test_helper"

class DatabaseCheckTest < Plastic::TestCase
  Check = Plastic::Graph::Database::Check

  def test_a_file_with_a_key_is_gated_and_one_without_is_prepared
    assert_equal [Plastic::Graph::Database::Gated, Plastic::Graph::Database::Prepared], [Check.for("", :local, "a.db", { nil => :local }).class, Check.for("", nil, "a.db", {}).class]
  end

  def test_the_key_of_a_check_is_the_key_of_its_schema
    assert_equal [:local, nil], [Check.for("", :local, "a.db", { nil => :local }).key, Check.for("", nil, "a.db", {}).key]
  end

  def test_a_prepared_check_builds_the_schema_once
    connection = SQLite3::Database.new(":memory:")
    check = Plastic::Graph::Database::Prepared.new("CREATE TABLE IF NOT EXISTS t(a);")
    check.call(connection)
    connection.execute("DROP TABLE t")
    check.call(connection)

    assert_empty connection.execute("SELECT name FROM sqlite_master WHERE name = 't'")
  end

  def test_a_check_that_was_passed_settles_nothing
    connection = SQLite3::Database.new(":memory:")
    check = Plastic::Graph::Database::Prepared.new("CREATE TABLE t(a);").tap(&:pass)
    check.call(connection)

    assert_empty connection.execute("SELECT name FROM sqlite_master")
  end

  def test_a_check_with_nothing_to_settle_refuses_the_call
    assert_raises(NoMethodError) { Check.new(nil).call(nil) }
  end
end
