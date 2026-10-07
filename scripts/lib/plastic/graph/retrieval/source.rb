# frozen_string_literal: true

require_relative "../database"
require_relative "../origin"
require_relative "../retrieval_graph"

module Plastic
  # Contains the persistence and retrieval components for Plastic graph records.
  module Graph
    module Retrieval
      # Opens only the databases and read graph that document retrieval needs.
      module Source
        def self.open(home:, store:)
          origin = Origin.new(home)
          root = File.join(home, "stores", store)
          databases = Database.open_local(home).merge(Database.open_store(root, origin))
          RetrievalGraph.new(databases, store:, origin:)
        end
      end
    end

    def self.open_retrieval(home:, store:) = Retrieval::Source.open(home:, store:)
  end
end
