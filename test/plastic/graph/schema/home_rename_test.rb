# frozen_string_literal: true

require_relative "../../../test_helper"

class SchemaHomeRenameTest < Plastic::TestCase
  Rename = Plastic::Graph::HomeRename

  def setup
    super
    @scratch = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@scratch)
    super
  end

  def file(name) = File.join(@scratch, name)

  def database(name)
    SQLite3::Database.new(file(name)).tap { |db| db.execute("CREATE TABLE t(a)") }.close
  end

  def test_the_file_and_its_wal_files_take_the_new_name
    database("local.db")
    %w[-journal -wal -shm].each { |suffix| File.write(file("local.db#{suffix}"), suffix) }
    Rename.new(file("local.db"), file("plastic.db")).call

    assert_equal %w[plastic.db plastic.db-journal plastic.db-shm plastic.db-wal], Dir.children(@scratch).sort
  end

  def test_the_rows_stay_with_the_renamed_file
    database("local.db")
    Rename.new(file("local.db"), file("plastic.db")).call

    assert_equal [["t"]], SQLite3::Database.new(file("plastic.db"), readonly: true).execute("SELECT name FROM sqlite_master")
  end

  def test_a_file_held_by_a_writer_is_not_renamed
    database("local.db")
    writer = SQLite3::Database.new(file("local.db"))
    writer.execute("BEGIN IMMEDIATE")
    assert_raises(SQLite3::BusyException) { Rename.new(file("local.db"), file("plastic.db"), timeout: 0).call }

    assert_includes Dir.children(@scratch), "local.db"
    refute_path_exists file("plastic.db")
  ensure
    writer&.close
  end

  def test_a_file_that_already_has_the_new_name_is_never_replaced
    database("local.db")
    database("plastic.db")

    assert_raises(Plastic::Graph::HomeRename::Taken) { Rename.new(file("local.db"), file("plastic.db")).call }
    assert_equal %w[local.db plastic.db], Dir.children(@scratch).sort
  end
end
