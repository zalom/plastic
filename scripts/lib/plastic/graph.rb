# frozen_string_literal: true

require_relative "graph/database"
require_relative "graph/retrieval_graph"
require_relative "graph/work_graph"

module Plastic
  # The graphs of one store. A writer writes its rows in one transaction; the
  # retrieval graph reads them. The databases sit at the home and hold every
  # store:
  #
  #   work        routine runs          work_graph.db
  #   retrieval   every read            no file of its own
  #
  # The report reads what the call wrote from `wrote`.
  module Graph
    # The open graphs of one store, and the databases they sit on.
    Graphs = Data.define(:work, :retrieval, :databases) do
      # One phrase per database that this call wrote to.
      def wrote = databases.values.filter_map(&:written_phrase)
    end

    def self.open(home:, store:)
      databases = Database.open_all(home)
      Graphs.new(work: WorkGraph.new(databases[:work], store:), retrieval: RetrievalGraph.new(databases, store:), databases:)
    end
  end
end
