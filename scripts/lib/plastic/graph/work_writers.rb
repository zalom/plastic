# frozen_string_literal: true

require "forwardable"
require_relative "completion_writer"
require_relative "session_writer"
require_relative "intent_writer"
require_relative "node_writer"
require_relative "edge_writer"
require_relative "ruling_writer"
require_relative "link_writer"
require_relative "roadmap_writer"
require_relative "sync"
require_relative "archive_writer"

module Plastic
  module Graph
    # The writers behind one work graph, each built on first use and bound to the same store.
    class WorkWriters
      extend Forwardable

      # The databases, folder, retrieval and session every writer is built on.
      Scope = Data.define(:databases, :retrieval, :folder, :session)

      def_delegators :@scope, :databases, :retrieval, :folder, :session

      def initialize(databases, retrieval, folder, session)
        @scope = Scope.new(databases:, retrieval:, folder:, session:)
        @built = {}
      end

      def completions = built(:completions) { CompletionWriter.new(databases, retrieval, folder, session:) }

      def sessions = built(:sessions) { SessionWriter.new(databases.fetch(:home), store: retrieval.store) }

      def intents = built(:intents) { IntentWriter.new(databases, retrieval, folder, session:) }

      def nodes = built(:nodes) { NodeWriter.new(databases, retrieval) }

      def edges = built(:edges) { EdgeWriter.new(databases, retrieval) }

      def rulings = built(:rulings) { RulingWriter.new(databases, retrieval, session:) }

      def links = built(:links) { LinkWriter.new(databases, retrieval) }

      def roadmaps = built(:roadmaps) { RoadmapWriter.new(databases, retrieval, session:) }

      def sync = built(:sync) { Sync.new(folder:, retrieval:, databases:) }

      def archives = built(:archives) { ArchiveWriter.new(databases, retrieval, folder, session:) }

      private

      def built(name) = (@built[name] ||= yield)
    end
  end
end
