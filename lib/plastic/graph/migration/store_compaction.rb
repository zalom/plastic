# frozen_string_literal: true

require_relative "../database"
require_relative "../schema"

module Plastic
  module Graph
    # Compacts each file of a migrated store, which moves it to incremental auto vacuum, and builds its search index again.
    module StoreCompaction
      def self.call(home, slug)
        root = File.join(home, "stores", slug)
        knowledge = File.join(root, Schema.file(:knowledge))
        connection = Database::ConnectionPool.for(knowledge, attach: Database::Store.attachments(knowledge))
        %w[main work retrieval].each { |schema| connection.execute_batch("PRAGMA #{schema}.auto_vacuum = INCREMENTAL; VACUUM #{schema}") }
        Database::ConnectionPool.release(root)
        Graph.open(home:, store: slug).retrieval.reindex
      end
    end
  end
end
