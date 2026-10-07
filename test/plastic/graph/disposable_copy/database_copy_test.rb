# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/disposable_copy"

module Plastic
  module Graph
    class DatabaseCopyTest < Plastic::TestCase
      def copy_into(home, copy) = DisposableCopy::DatabaseCopy.new(home, copy, "global").call

      def test_each_database_of_the_home_and_the_store_lands_in_the_copy
        with_home do |home|
          seed_intents(home, "Alpha")
          copy = File.join(File.dirname(home), "copy")
          copy_into(home, copy)

          assert_path_exists File.join(copy, "local.db")
          assert_path_exists File.join(copy, "stores", "global", "work_graph.db")
        end
      end

      def test_a_home_db_not_yet_renamed_keeps_its_name_in_the_copy
        with_home do |home|
          seed_intents(home, "Alpha")
          Database::ConnectionPool.release(home)
          File.rename(File.join(home, "local.db"), File.join(home, "home.db"))
          copy = File.join(File.dirname(home), "copy")
          copy_into(home, copy)

          assert_path_exists File.join(copy, "home.db")
          refute_path_exists File.join(copy, "local.db")
        end
      end
    end
  end
end
