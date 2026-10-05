# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeBackupPurgerTest < Plastic::TestCase
  include BackupHomes

  Purger = Plastic::Graph::Knowledge::Backup::Purger

  def test_a_failed_row_delete_puts_the_folder_back
    home = fresh_home
    backup_at(home, at(2026, 1, 1, 10, 0, 0))
    home_db = Plastic::Graph.open(home:, store: "alpha").databases.fetch(:home)
    home_db.execute("DROP TABLE backups")
    purger = Purger.new(home_db, File.join(home, "stores", "alpha"), "alpha")

    assert_raises(StandardError) { purger.remove("20260101100000") }
    assert_equal ["20260101100000"], folder_names(home)
    assert_equal 3, Dir.children(File.join(backups_dir(home), "20260101100000")).size
  end

  def test_names_before_a_time_are_strictly_older
    home = fresh_home
    backup_at(home, at(2026, 2, 28, 23, 59, 59))
    backup_at(home, at(2026, 3, 1, 0, 0, 0))
    purger = Purger.new(nil, File.join(home, "stores", "alpha"), "alpha")

    assert_equal ["20260228235959"], purger.names(older_than: at(2026, 3, 1, 0, 0, 0))
  end
end
