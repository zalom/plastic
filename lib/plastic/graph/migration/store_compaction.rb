# frozen_string_literal: true

require_relative "../database"
require_relative "../schema"

module Plastic
  module Graph
    # Compacts each file of a store, which moves it to incremental auto vacuum, and builds its search index again.
    module StoreCompaction
      INCREMENTAL = 2
      FILES = %i[knowledge work retrieval].freeze

      def self.call(home, slug)
        root = File.join(home, "stores", slug)
        knowledge = File.join(root, Schema.file(:knowledge))
        connection = Database::ConnectionPool.for(knowledge, attach: Database::Store.attachments(knowledge))
        %w[main work retrieval].each { |schema| connection.execute_batch("PRAGMA #{schema}.auto_vacuum = INCREMENTAL; VACUUM #{schema}") }
        Database::ConnectionPool.release(root)
        Graph.open(home:, store: slug).retrieval.reindex
      end

      # Whether a file of the store in `root` is not on incremental auto vacuum yet, as after a compaction that failed.
      def self.due?(root)
        FILES.map { |key| File.join(root, Schema.file(key)) }.select { |file| File.file?(file) }.any? { |file| vacuum_mode(file) != INCREMENTAL }
      end

      def self.vacuum_mode(file)
        database = SQLite3::Database.new(file, readonly: true)
        database.get_first_value("PRAGMA auto_vacuum")
      ensure
        database&.close
      end
    end
  end
end
