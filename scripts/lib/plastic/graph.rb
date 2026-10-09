# frozen_string_literal: true

require "fileutils"
require_relative "graph/database"
require_relative "graph/missing_store"
require_relative "graph/origin"
require_relative "graph/retrieval_graph"
require_relative "graph/knowledge/store_folder"
require_relative "graph/work_graph"

module Plastic
  # The graphs of one store. The home keeps local.db, for the routine runs of
  # this machine. The store folder keeps work_graph.db, knowledge_graph.db
  # and references.db, and the files printed from their rows. A writer
  # writes its rows in one transaction per database; the retrieval graph
  # reads them. The report reads what the call wrote from `wrote`.
  module Graph
    # The open graphs of one store, and the databases they sit on.
    Graphs = Data.define(:work, :retrieval, :databases) do
      # One phrase per database that this call wrote to, after any rename it made.
      def wrote = databases.values.flat_map(&:phrases)
    end

    # Opening refuses a store folder that does not exist, and reads no file
    # and makes none: the origin id and the databases appear on the first
    # read or write. `session` names the harness session that made the call,
    # stamped on the rows it writes.
    def self.open(home:, store:, session: nil)
      root = Database.store_root(home, store)
      origin = Origin.new(home)
      databases = Database.open_local(home).merge(Database.open_store(root, origin))
      retrieval = RetrievalGraph.new(databases, store:, origin:)
      Graphs.new(work: WorkGraph.new(databases, folder: Knowledge::StoreFolder.new(root), retrieval:, session:), retrieval:, databases:)
    end

    # Makes the store folder and its databases, then opens it. The one way
    # a store comes to exist.
    def self.create(home:, store:, session: nil)
      FileUtils.mkdir_p(File.join(home, "stores", store))
      opened = Graph.open(home:, store:, session:)
      opened.databases.values_at(:knowledge, :work, :references).each { |database| database.rows("SELECT 1") }
      opened
    end
  end
end
