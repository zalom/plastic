# frozen_string_literal: true

require_relative "../../../test_helper"

class SchemaHomeCopyTest < Plastic::TestCase
  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  def filled_database(path)
    db = SQLite3::Database.new(path)
    db.execute("CREATE TABLE filler (id INTEGER PRIMARY KEY, body TEXT)")
    db.transaction { 2000.times { |index| db.execute("INSERT INTO filler (body) VALUES (?)", ["row #{index} " * 40]) } }
    db.close
  end

  def damaged_database
    File.join(@scratch, "local.db").tap do |path|
      filled_database(path)
      File.binwrite(path, File.binread(path).tap { |bytes| bytes[bytes.bytesize - (4096 * 20) + 8, 40] = ("\xFF" * 40).b })
    end
  end

  def setup
    super
    @scratch = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@scratch)
    super
  end

  def test_a_database_that_fails_the_quick_check_leaves_no_copy
    folder = File.join(@scratch, "backups")
    error = assert_raises(SQLite3::CorruptException) { Plastic::Graph::HomeCopy.new(damaged_database, folder, NOW).call }

    assert_match(/fails the quick check/, error.message)
    assert_empty Dir.glob(File.join(folder, "*"))
  end

  def test_a_copy_already_at_the_target_is_kept_and_the_call_raises
    path = File.join(@scratch, "plastic.db")
    filled_database(path)
    first = Plastic::Graph::HomeCopy.new(path, File.join(@scratch, "backups"), NOW).call
    before = File.binread(first)

    assert_raises(Plastic::Graph::HomeCopy::Exists) { Plastic::Graph::HomeCopy.new(path, File.join(@scratch, "backups"), NOW).call }
    assert_equal before, File.binread(first)
  end

  def test_the_copy_is_named_after_its_file
    path = File.join(@scratch, "plastic.db")
    filled_database(path)

    assert_equal File.join(@scratch, "backups", "plastic-20261116120000.db"), Plastic::Graph::HomeCopy.new(path, File.join(@scratch, "backups"), NOW).call
  end
end
