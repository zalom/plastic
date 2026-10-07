# frozen_string_literal: true

require "forwardable"
require_relative "completion/writer"
require_relative "session/writer"
require_relative "../knowledge/intent/writer"
require_relative "node/writer"
require_relative "edge/writer"
require_relative "../knowledge/ruling/writer"
require_relative "../knowledge/link/writer"
require_relative "../knowledge/roadmap/writer"
require_relative "../knowledge/sync"
require_relative "../knowledge/archive/writer"

module Plastic
  module Graph
    module Work
      # The writers behind one work graph, each built on first use and bound to the same store.
      class Writers
        extend Forwardable

        # The databases, folder, retrieval and session every writer is built on.
        Scope = Data.define(:databases, :retrieval, :folder, :session)

        def_delegators :@scope, :databases, :retrieval, :folder, :session

        def initialize(databases, retrieval, folder, session)
          @scope = Scope.new(databases:, retrieval:, folder:, session:)
          @built = {}
        end

        def completions = built(:completions) { Completion::Writer.new(databases, retrieval, folder, session:) }

        def sessions = built(:sessions) { Session::Writer.new(databases.fetch(:local), store: retrieval.store) }

        def intents = built(:intents) { Knowledge::Intent::Writer.new(databases, retrieval, folder, session:) }

        def nodes = built(:nodes) { Node::Writer.new(databases, retrieval) }

        def edges = built(:edges) { Edge::Writer.new(databases, retrieval) }

        def rulings = built(:rulings) { Knowledge::Ruling::Writer.new(databases, retrieval, session:) }

        def links = built(:links) { Knowledge::Link::Writer.new(databases, retrieval) }

        def roadmaps = built(:roadmaps) { Knowledge::Roadmap::Writer.new(databases, retrieval, session:) }

        def sync = built(:sync) { Knowledge::Sync.new(folder:, retrieval:, databases:) }

        def archives = built(:archives) { Knowledge::Archive::Writer.new(databases, retrieval, folder, session:) }

        private

        def built(name) = (@built[name] ||= yield)
      end
    end
  end
end
