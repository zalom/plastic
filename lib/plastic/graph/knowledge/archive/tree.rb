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
            stat = File.lstat(path)
            entry = entry_for(relative, path, stat)
            children = stat.directory? ? children_of(path, relative) : []
            [entry, *children]
          end

          def children_of(path, relative)
            Dir.children(path).sort.flat_map { |name| visit(relative.empty? ? name : File.join(relative, name)) }
          end

          def entry_for(relative, path, stat)
            raise Error, "cannot archive special file #{path}" unless stat.file? || stat.directory? || stat.symlink?

            { path: relative, kind: stat.ftype, mode: stat.mode & 0o7777,
              mtime: stat.mtime.to_r.to_s, data: content(path, stat) }
          end

          def content(path, stat)
            return File.binread(path) if stat.file?
            return File.readlink(path).b if stat.symlink?

            nil
          end
        end
      end
    end
  end
end
