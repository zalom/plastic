# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Writes the rulings and links that Decisions read, and counts them in the table totals it was given.
        class DecisionWriter
          def initialize(databases, counts, clock:)
            @store = databases.fetch(:store)
            @counts = counts
            @clock = clock
          end

          def call(decisions) = decisions.each { |decision| write(decision) }

          private

          def write(decision)
            intent_id = decision.fetch(:intent_id)
            decision.fetch(:rulings).each { |id, text| insert(:rulings, { intent_id:, id:, text:, supersedes: nil, at: stamp, session_id: nil }) }
            links(intent_id, decision.fetch(:source), "source")
            links(intent_id, decision.fetch(:chain), "chain")
          end

          def links(intent_id, refs, kind) = refs.each { |ref| insert(:links, { from_ref: intent_id, to_ref: ref, kind:, at: stamp }) }

          def insert(table, row)
            @store.transaction { |batch| batch.put(table, row, statement: :insert) }
            @counts[table] += 1
          end

          def stamp = Plastic.timestamp(@clock.now)
        end
      end
    end
  end
end
