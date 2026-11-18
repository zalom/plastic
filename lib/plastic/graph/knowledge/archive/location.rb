# frozen_string_literal: true

require_relative "../archive"
require_relative "tree"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Archive paths are direct children of the store's real intent directory.
        module Location
          def self.root(folder, intent)
            dir = intent.dir
            validate(dir)
            parent = folder.path("store")
            raise Tree::Error, "archive parent must be a directory, not a link" unless File.directory?(parent) && !File.symlink?(parent)

            folder.path(dir)
          end

          def self.validate(relative)
            parts = relative.split("/", -1)
            leaf = parts.last
            return if parts.size == 2 && parts.first == "store" && !["", ".", ".."].include?(leaf) && !leaf.include?("\0")

            raise Tree::Error, "invalid intent archive directory #{relative}"
          end
        end
      end
    end
  end
end
