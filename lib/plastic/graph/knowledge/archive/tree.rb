# frozen_string_literal: true

require_relative "../archive"
require "fileutils"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Reads an intent tree without following links. Paths are relative to its root.
        class Tree
          class Error < StandardError; end

          def self.read(root)
            return [] unless File.exist?(root) || File.symlink?(root)

            new(root).read
          end

          def initialize(root)
            @root = root
          end

          def read
            raise Error, "archive root must be a directory, not a link" unless File.directory?(@root) && !File.symlink?(@root)

            visit("")
          end

          private

          def visit(relative)
            path = relative.empty? ? @root : File.join(@root, relative)
            node = Node.new(relative, path, File.lstat(path))
            [node.entry, *(node.directory? ? children_of(path, relative) : [])]
          end

          def children_of(path, relative)
            Dir.children(path).sort.flat_map { |name| visit(relative.empty? ? name : File.join(relative, name)) }
          end

          # One path of the tree with its link-free stat, which becomes one snapshot entry.
          class Node
            def initialize(relative, path, stat)
              @relative = relative
              @path = path
              @stat = stat
            end

            def directory? = @stat.directory?

            def entry
              raise Error, "cannot archive special file #{@path}" unless @stat.file? || @stat.directory? || @stat.symlink?

              { path: @relative, kind: @stat.ftype, mode: @stat.mode & 0o7777, mtime: @stat.mtime.to_r.to_s, data: content }
            end

            private

            def content
              return File.binread(@path) if @stat.file?

              File.readlink(@path).b if @stat.symlink?
            end
          end
        end
      end
    end
  end
end
