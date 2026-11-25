# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/disposable_copy"

module Plastic
  module Graph
    class DatabaseCopyTest < Plastic::TestCase
      def copy_into(home, copy) = DisposableCopy::DatabaseCopy.new(home, copy, "global").call

      def test_each_database_of_the_home_and_the_store_lands_in_the_copy
        with_home do |home|
          seed_intents(home, "Alpha")
          copy = File.join(File.dirname(home), "copy")
          copy_into(home, copy)

          assert_path_exists File.join(copy, "plastic.db")
          assert_path_exists File.join(copy, "stores", "global", "work_graph.db")
        end
      end

      def test_a_store_database_file_that_is_missing_is_left_out_of_the_copy
        with_home do |home|
          seed_intents(home, "Alpha")
          File.delete(File.join(home, "stores", "global", "retrieval.db")) if File.exist?(File.join(home, "stores", "global", "retrieval.db"))
          File.delete(File.join(home, "stores", "global", "work_graph.db"))
          copy = File.join(File.dirname(home), "copy")
          copy_into(home, copy)

          refute_path_exists File.join(copy, "stores", "global", "work_graph.db")
        end
      end

      def test_a_home_with_no_machine_database_copies_only_the_store_databases
        with_home do |home|
          seed_intents(home, "Alpha")
          File.delete(File.join(home, "plastic.db"))
          copy = File.join(File.dirname(home), "copy")
          copy_into(home, copy)

          assert_equal [false, true], [File.exist?(File.join(copy, "plastic.db")), File.exist?(File.join(copy, "stores", "global", "work_graph.db"))]
        end
      end
    end
  end
end
