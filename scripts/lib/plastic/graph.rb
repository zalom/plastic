# frozen_string_literal: true

require_relative "graph/database"
require_relative "graph/origin"
require_relative "graph/retrieval_graph"
require_relative "graph/store_folder"
require_relative "graph/work_graph"

module Plastic
  # The graphs of one store. The home keeps home.db, for the routine runs of
  # this machine. The store folder keeps work_graph.db, knowledge_graph.db
  # and references.db, and the files printed from their rows. A writer
  # writes its rows in one transaction per database; the retrieval graph
  # reads them. The report reads what the call wrote from `wrote`.
  module Graph
    # The open graphs of one store, and the databases they sit on.
    Graphs = Data.define(:work, :retrieval, :databases) do
      # One phrase per database that this call wrote to.
      def wrote = databases.values.filter_map(&:written_phrase)
    end

    # Opening reads no file and makes none: the origin id and the databases
    # appear on the first read or write. `engine` runs the databases' scripts.
    def self.open(home:, store:, engine: Database::Program.new)
      origin = Origin.new(home)
      root = File.join(home, "stores", store)
      databases = Database.open_home(home, engine:).merge(Database.open_store(root, origin, engine:))
      retrieval = RetrievalGraph.new(databases, store:, origin:)
      Graphs.new(work: WorkGraph.new(databases, folder: StoreFolder.new(root), retrieval:), retrieval:, databases:)
    end
  end
end
