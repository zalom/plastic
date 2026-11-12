# frozen_string_literal: true

require "fileutils"
require_relative "../schema"

module Plastic
  module Graph
    class DisposableCopy
      # The databases of one home and one store, written into the copy as a
      # consistent snapshot. A home.db not yet renamed keeps its name, and
      # the copy renames it on first use.
      class DatabaseCopy
        def initialize(home, copy, slug)
          @home = home
          @copy = copy
          @slug = slug
        end

        def call
          sources.each do |name, source|
            target = File.join(@copy, name)
            FileUtils.mkdir_p(File.dirname(target))
            Database::ConnectionPool.for(source).execute("VACUUM INTO ?", [target])
          end
        end

        private

        def sources = [local, *Schema.store.filter_map { |key| store_entry(key) }].compact

        def local = [Schema.file(:local), "home.db"].map { |file| [file, File.join(@home, file)] }.find { |_file, path| File.file?(path) }

        def store_entry(key)
          file = Schema.file(key)
          path = File.join(@home, "stores", @slug, file)
          ["stores/#{@slug}/#{file}", path] if File.exist?(path)
        end
      end
    end
  end
end
