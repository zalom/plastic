# frozen_string_literal: true

require_relative "../../../test_helper"

class SchemaRunnerReasonsTest < Plastic::TestCase
  include BackupHomes
  include OldLayoutHomes

  NOW = Time.utc(2026, 11, 16, 12, 0, 0)

  def failure(home) = Plastic::Graph::SchemaRunner.new(home:, now: NOW).call.failed.fetch("alpha")

  def test_a_store_with_a_file_that_is_not_a_database_gives_the_file_in_its_reason
    home = old_layout(fresh_home)
    Plastic::Graph::Database::ConnectionPool.release(home)
    File.write(store_file(home, "work_graph"), "not a database")

    assert_match(/\Ait could not be migrated \(.*work_graph\.db.*\)\z/, failure(home))
  end

  def test_a_store_whose_backup_folder_cannot_be_written_gives_the_backup_as_its_reason
    home = old_layout(fresh_home)
    FileUtils.mkdir_p(File.join(home, "stores", "alpha", "backups"), mode: 0o555)

    assert_match(/\Aits backup failed \(.+\)\z/, failure(home))
  end
end
