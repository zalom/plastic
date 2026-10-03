# frozen_string_literal: true

require_relative "../hook"
require_relative "../graph"
require_relative "recap"

module Plastic
  module Hooks
    # SessionStart: opens the session row, then prints the Recap the rows
    # alone carry. Nothing here is call memory: a hook keeps no routine run.
    class Resume < Hook
      option :harness, switch: "--harness NAME", text: "the harness calling this hook", default: "claude-code"

      def respond(event)
        graphs = Graph.open(home: scope.plastic_home, store: scope.slug, session: session_id)
        open_session_row(graphs.work)
        Recap.new(graphs.retrieval, session_id:, source: event[:source], directory:).lines.join("\n")
      end

      private

      # The store's databases stay out of its versioning before any read.
      def open_session_row(work)
        work.ignore_databases
        return environment.err.puts("plastic hook: the event names no session; nothing recorded") unless session_id

        work.open_session(session_id, harness: parsed[:harness], directory:)
      end
    end
  end
end
