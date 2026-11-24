# frozen_string_literal: true

require_relative "driver/writer"

module Plastic
  module Graph
    module Work
      # One lapsed claim of an intent in agent delivery: its driver claim, or the claim of one of its nodes. `claim` is
      # "driver" or "node"; `agent` is the agent of the node's open run, nil for a driver claim or a run with none.
      # `last_renewed` is the stored UTC time of the last renewal.
      LapsedClaim = Data.define(:store, :intent_id, :title, :claim, :node, :node_title, :agent, :session, :last_renewed) do
        def driver? = claim == "driver"
      end

      # The lapsed claims of one store's intents in agent delivery, at `now`: for each intent that plastic intent auto
      # drives, its driver claim when it lapsed, then each claimed node whose claim lapsed. It reads and changes nothing.
      class LapsedClaims
        NO_NODE = { node: nil, node_title: nil, agent: nil }.freeze

        def initialize(retrieval, store:, now:)
          @retrieval = retrieval
          @store = store
          @now = now
        end

        def to_a
          nodes = @retrieval.claimed_nodes.select { |node| node.lapsed?(@now) }.group_by(&:intent_id)
          @retrieval.agent_drivers.flat_map { |row| [driver(row), *nodes.fetch(row["intent_id"], []).map { |node| node_claim(row, node) }].compact }
        end

        private

        def driver(row)
          return unless Driver::Held.from(row, now: @now, ended: false).lapsed

          claim(row, "driver", session: row["session_id"], last_renewed: stamp(row["seen_at"], row["claimed_at"]), **NO_NODE)
        end

        def node_claim(row, node)
          claim(row, "node", node: node.id, node_title: node.title, agent: agent(node), session: node.claimed_by, last_renewed: stamp(node.seen_at, node.claimed_at))
        end

        def claim(row, kind, **fields) = LapsedClaim.new(store: @store, intent_id: row["intent_id"], title: row["title"], claim: kind, **fields)

        def agent(node) = @retrieval.structure.runs(node.intent_id).reverse.find { |run| run.node_id == node.id && run.open? }&.agent

        def stamp(*stamps) = stamps.find { |value| !value.to_s.empty? }
      end
    end
  end
end
