# frozen_string_literal: true

require_relative "../database"
require_relative "../schema"

module Plastic
  module Graph
    # Compacts the knowledge and work files of a migrated store and builds its search index again.
    module StoreCompaction
      def self.call(home, slug)
        root = File.join(home, "stores", slug)
        knowledge = File.join(root, Schema.file(:knowledge))
        connection = Database::ConnectionPool.for(knowledge, attach: Database::Store.attachments(knowledge))
        %w[main work].each { |schema| connection.execute("VACUUM #{schema}") }
        Database::ConnectionPool.release(root)
        Graph.open(home:, store: slug).retrieval.reindex
      end
    end
  end
end
