# frozen_string_literal: true

require_relative "database"
require_relative "origin"
require_relative "retrieval_graph"

module Plastic
  # Contains the persistence and retrieval components for Plastic graph records.
  module Graph
    # Opens only the databases and read graph that document retrieval needs.
    module RetrievalSource
      def self.open(home:, store:, clock: Time)
        origin = Origin.new(home)
        root = Database.store_root(home, store)
        databases = Database.open_local(home).merge(store: Database.open_store(root, origin))
        RetrievalGraph.new(databases, store:, origin:, clock:)
      end
    end

    def self.open_retrieval(home:, store:) = RetrievalSource.open(home:, store:)
  end
end
