# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/workflows/code/migration"

class WorkflowsCodeMigrationTest < Plastic::TestCase
  Migration = Plastic::Workflows::Code::Migration

  def test_an_event_that_moved_nothing_counts_no_rows
    assert_equal "no rows", Migration.counted({})
  end

  def test_one_row_of_one_table_counts_as_one_row
    assert_equal "1 row of sqlar", Migration.counted({ "sqlar" => 1 })
  end

  def test_rows_of_three_tables_are_counted_with_commas_and_an_and_before_the_last
    assert_equal "2 rows of document_revisions, 1 row of sqlar and 0 rows of links",
      Migration.counted({ "document_revisions" => 2, "sqlar" => 1, "links" => 0 })
  end
end
