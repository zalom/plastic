# frozen_string_literal: true

require_relative "../../../test_helper"

class FormerNameTest < Plastic::TestCase
  FormerName = Plastic::Graph::Database::FormerName

  def setup
    super
    @folder = Dir.mktmpdir("former-name")
  end

  def teardown
    FileUtils.rm_rf(@folder)
    super
  end

  attr_reader :folder

  def file(name) = File.join(folder, name)

  def former = FormerName.new(file("home.db"))

  def test_the_file_and_its_rollback_journal_move_to_the_new_name
    File.write(file("home.db"), "rows")
    File.write(file("home.db-journal"), "journal")

    assert_equal "home.db renamed to local.db", former.move_to(file("local.db"))
    assert_equal %w[local.db local.db-journal], Dir.children(folder).sort
    assert_equal %w[rows journal], [File.read(file("local.db")), File.read(file("local.db-journal"))]
  end

  def test_the_write_ahead_log_and_shared_memory_files_move_too
    %w[home.db home.db-wal home.db-shm].each { |name| File.write(file(name), name) }
    former.move_to(file("local.db"))

    assert_equal %w[local.db local.db-shm local.db-wal], Dir.children(folder).sort
  end

  def test_an_existing_file_under_the_new_name_is_kept_and_the_former_file_left_alone
    File.write(file("home.db"), "old")
    File.write(file("local.db"), "new")

    assert_nil former.move_to(file("local.db"))
    assert_equal %w[old new], [File.read(file("home.db")), File.read(file("local.db"))]
  end

  def test_no_former_file_moves_nothing
    assert_nil former.move_to(file("local.db"))
    assert_empty Dir.children(folder)
  end
end

class LocalDatabaseFirstUseTest < Plastic::TestCase
  def machine = File.join(@home, "machine")

  def home_db_from_before
    Plastic::Graph::Database.new(File.join(machine, "home.db"), Plastic::Graph::Schema.fetch(:local)).transaction do |batch|
      batch.insert(:routine_runs, { store: "s", tool: "t", subject: "a" })
    end
    Plastic::Graph::Database::ConnectionPool.release(machine)
  end

  def first_use = Plastic::Graph::Database.open_local(machine).fetch(:local).tap { |local| local.rows("SELECT 1") }

  def test_a_home_db_left_from_before_becomes_local_db_on_first_use
    home_db_from_before

    assert_equal ["a"], first_use.rows("SELECT subject FROM routine_runs").map { |row| row.fetch("subject") }
    assert_equal [false, true], [File.exist?(File.join(machine, "home.db")), File.exist?(File.join(machine, "local.db"))]
  end

  def test_only_the_call_that_renamed_the_file_says_so
    home_db_from_before

    assert_equal [["home.db renamed to local.db"], []], [first_use.phrases, first_use.phrases]
  end

  def test_opening_renames_nothing_before_the_first_use
    home_db_from_before
    Plastic::Graph::Database.open_local(machine)

    assert_equal [true, false], [File.exist?(File.join(machine, "home.db")), File.exist?(File.join(machine, "local.db"))]
  end
end
