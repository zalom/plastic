# frozen_string_literal: true

require "tmpdir"
require_relative "database"
require_relative "disposable_copy/store_tree"

module Plastic
  module Graph
    # A throwaway copy of one store and its home files, for a call that must
    # show what it would do and change nothing. The databases are snapshotted
    # with VACUUM INTO and the files are copied; a link to a file is copied
    # as a link to a copy of its target, and a link to a folder is refused.
    # The copy and its connections are gone when the block ends.
    class DisposableCopy
      # The home holds something the copy cannot hold safely.
      class Refused < StandardError; end

      attr_reader :path

      def initialize(home, slug)
        @home = home
        @slug = slug
        @path = nil
        @tree = nil
      end

      def within
        Dir.mktmpdir("plastic-preview") do |root|
          @path = File.join(root, "home")
          @tree = StoreTree.new(@home, @path, @slug).populate
          yield self
        ensure
          Database::ConnectionPool.release(root)
        end
      end

      # The text with the copy's path read as the original's.
      def original(text) = text.gsub(path, @home)

      # Each file the call would add, change or remove, by original path.
      def changes = @tree.changes
    end
  end
end
