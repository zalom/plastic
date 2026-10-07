# frozen_string_literal: true

require_relative "../../../test_helper"

class FormerNameTest < Plastic::TestCase
  FormerName = Plastic::Graph::Database::FormerName

  def folder = File.join(@home, "machine").tap { |path| FileUtils.mkdir_p(path) }

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
