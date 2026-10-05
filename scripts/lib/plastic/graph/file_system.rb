# frozen_string_literal: true

require "fileutils"

module Plastic
  module Graph
    # The file moves a writer can lose midway. A writer takes one as an
    # argument, so a test passes a subclass that fails one move.
    class FileSystem
      def initialize(file: File, utils: FileUtils)
        @file = file
        @utils = utils
      end

      def rename(from, to) = @file.rename(from, to)

      def remove_entry(path) = @utils.remove_entry(path)

      def copy_tree(source, destination) = @utils.cp_r(source, destination)
    end
  end
end
