# frozen_string_literal: true

require "fileutils"
require_relative "graph/database"
require_relative "graph/missing_store"
require_relative "graph/origin"
require_relative "graph/migration/runner"
require_relative "graph/retrieval_graph"
require_relative "graph/knowledge/store_folder"
require_relative "graph/knowledge/sync_settings"
require_relative "graph/work_graph"

module Plastic
  # The graphs of one store. The home keeps plastic.db, for the command runs of
  # this machine. The store folder keeps work_graph.db, knowledge_graph.db
  # and retrieval_graph.db, and the files printed from their rows. A writer
  # writes its rows in one transaction over the store; the retrieval graph
  # reads them. The report reads what the call wrote from `wrote`.
  module Graph
    # The open graphs of one store, and the databases they sit on.
    Graphs = Data.define(:work, :retrieval, :databases) do
      # The files this call printed, relative to the store folder.
      def printed = work.printed

      # One phrase per database that this call wrote to, after any rename it made.
      def wrote = databases.values.flat_map(&:phrases)

      def wrote_rows? = databases.values.any?(&:wrote_rows?)
    end

    # Opening refuses a store folder that does not exist, and reads no file
    # and makes none: the origin id and the databases appear on the first
    # read or write. `session` names the harness session that made the call,
    # stamped on the rows it writes.
    def self.open(home:, store:, session: nil, clock: Time, sync: Knowledge::SyncSettings.none)
      root = Database.store_root(home, store)
      origin = Origin.new(home)
      databases = Database.open_local(home).merge(store: Database.open_store(root, origin))
      retrieval = RetrievalGraph.new(databases, store:, origin:, clock:)
      folder = Knowledge::StoreFolder.new(root, sync: sync.for_store(databases.fetch(:store)))
      Graphs.new(work: WorkGraph.new(databases, folder:, retrieval:, session:, clock:), retrieval:, databases:)
    end

    # Makes the store folder and its databases, then opens it. The one way
    # a store comes to exist.
    def self.create(home:, store:, session: nil)
      FileUtils.mkdir_p(File.join(home, "stores", store))
      ready(Graph.open(home:, store:, session:))
    end

    def self.ready(graphs)
      graphs.databases.each_value { |database| database.rows("SELECT 1") }
      graphs
    end
  end
end
