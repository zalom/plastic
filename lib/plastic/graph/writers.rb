# frozen_string_literal: true

require "forwardable"
require_relative "work/completion/writer"
require_relative "work/session/writer"
require_relative "knowledge/intent/writer"
require_relative "knowledge/intent/reviser"
require_relative "work/node/writer"
require_relative "work/edge/writer"
require_relative "work/approval/writer"
require_relative "work/verdict/writer"
require_relative "knowledge/ruling/writer"
require_relative "knowledge/link/writer"
require_relative "knowledge/sync"
require_relative "knowledge/archive/writer"
require_relative "writers_scope"

module Plastic
  module Graph
    # The writers behind one work graph, each built on first use and bound to the same store.
    class Writers
      extend Forwardable

      def_delegators :@scope, :databases, :retrieval, :folder, :session, :clock, :drivers, :release

      def initialize(databases, retrieval, folder, session, clock = Time)
        @scope = Scope.new(databases:, retrieval:, folder:, session:, clock:)
        @built = {}
      end

      def completions = built(:completions) { Work::Completion::Writer.new(databases, retrieval, folder, session:) }

      def sessions = built(:sessions) { Work::Session::Writer.new(databases.fetch(:local), store: retrieval.store, clock:) }

      def intents = built(:intents) { Knowledge::Intent::Writer.new(databases, retrieval, folder, session:) }

      def revisions = built(:revisions) { Knowledge::Intent::Reviser.new(databases, retrieval, clock:) }

      def nodes = built(:nodes) { Work::Node::Writer.new(databases, retrieval, clock:) }

      def edges = built(:edges) { Work::Edge::Writer.new(databases, retrieval) }

      def approvals = built(:approvals) { Work::Approval::Writer.new(databases, retrieval, session:, clock:) }

      def verdicts = built(:verdicts) { Work::Verdict::Writer.new(databases, retrieval, session:, clock:) }

      def rulings = built(:rulings) { Knowledge::Ruling::Writer.new(databases, retrieval, session:, clock:) }

      def links = built(:links) { Knowledge::Link::Writer.new(databases, retrieval, clock:) }

      def sync = built(:sync) { Knowledge::Sync.new(folder:, retrieval:, databases:) }

      def archives = built(:archives) { Knowledge::Archive::Writer.new(databases, retrieval, folder, session:, clock:) }

      private

      def built(name) = (@built[name] ||= yield)
    end
  end
end
