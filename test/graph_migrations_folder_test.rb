# frozen_string_literal: true

require "minitest/autorun"

# The two SQL migrations are the only files of the migrations folder, one for each sequence.
class GraphMigrationsFolderTest < Minitest::Test
  FOLDER = File.expand_path("../lib/plastic/graph/schema/migrations", __dir__)

  def test_the_folder_holds_the_store_migration
    assert_includes Dir.children(FOLDER), "store_from_beta_2.sql"
  end

  def test_the_folder_holds_nothing_but_sql_files
    assert_empty Dir.children(FOLDER).reject { |name| name.end_with?(".sql") }
  end
end
