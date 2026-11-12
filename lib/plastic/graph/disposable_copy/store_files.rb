# frozen_string_literal: true

require "fileutils"
require "find"
require_relative "snapshot"

module Plastic
  module Graph
    class DisposableCopy
      # The files of one store copied under another path, databases left
      # out. A link to a file becomes a link to a held copy of its target,
      # so a write through it never reaches the original.
      class StoreFiles
        attr_reader :target

        def initialize(home, target, slug)
          @home = home
          @target = target
          @root = File.join(home, "stores", slug)
        end

        def refuse_folder_links
          return unless File.exist?(@root) || File.symlink?(@root)

          Find.find(@root) do |path|
            raise Refused, "preview cannot copy folder link #{path}; the original store was not changed" if File.symlink?(path) && File.directory?(path)
          end
        end

        def call
          return unless File.directory?(@root)

          Find.find(@root) { |path| place(path, File.join(@target, path.delete_prefix("#{@home}/"))) }
        end

        private

        def place(path, copied)
          link = File.symlink?(path)
          return FileUtils.mkdir_p(copied) if File.directory?(path) && !link
          return if Snapshot::DATABASE.match?(path)

          link ? copy_link(path, copied) : StoreTree.copy_file(path, copied)
        end

        def copy_link(source, copied)
          held = File.join(File.dirname(@target), "sandbox", copied.delete_prefix("#{@target}/"))
          File.file?(source) ? StoreTree.copy_file(source, held) : FileUtils.mkdir_p(File.dirname(held))
          FileUtils.mkdir_p(File.dirname(copied))
          File.symlink(held, copied)
        end
      end
    end
  end
end
