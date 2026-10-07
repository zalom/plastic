# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../scripts/lib/plastic/graph/disposable_copy"

module Plastic
  module Graph
    class StoreFilesTest < Plastic::TestCase
      def files(home) = DisposableCopy::StoreFiles.new(home, File.join(File.dirname(home), "copy"), "global")

      def store_file(root, *rest) = File.join(root, "stores", "global", *rest)

      def test_the_store_files_land_in_the_copy_without_the_databases
        with_home do |home|
          seed_intents(home, "Alpha")
          File.write(store_file(home, "notes.txt"), "kept\n")
          copy = files(home).tap(&:call)

          assert_equal "kept\n", File.read(store_file(copy.target, "notes.txt"))
          refute_path_exists store_file(copy.target, "work_graph.db")
        end
      end

      def test_a_link_to_a_folder_refuses_naming_the_link
        with_home do |home|
          seed_intents(home, "Alpha")
          outside = File.join(File.dirname(home), "outside")
          FileUtils.mkdir_p(outside)
          File.symlink(outside, store_file(home, "folder"))
          error = assert_raises(DisposableCopy::Refused) { files(home).refuse_folder_links }

          assert_includes error.message, store_file(home, "folder")
        end
      end
    end
  end
end
