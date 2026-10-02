# frozen_string_literal: true

require_relative "archive_tree"

module Plastic
  module Graph
    # Archive paths are direct children of the store's real intent directory.
    module ArchiveLocation
      def self.root(folder, intent)
        validate(intent.dir)
        parent = folder.path("store")
        raise ArchiveTree::Error, "archive parent must be a directory, not a link" unless File.directory?(parent) && !File.symlink?(parent)

        folder.path(intent.dir)
      end

      def self.validate(relative)
        parts = relative.split("/", -1)
        return if parts.size == 2 && parts.first == "store" && !["", ".", ".."].include?(parts.last) && !parts.last.include?("\0")

        raise ArchiveTree::Error, "invalid intent archive directory #{relative}"
      end
    end
  end
end
