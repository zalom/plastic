# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      class Session
        # Intent ids one session touched, most recent first: routine runs of
        # the store with the session id, and savepoint lines with the session
        # id (review A6: a line sync up rewrote from the file carries no
        # session, so it never counts here).
        class Touched
          # A routine run names the intent_id its facts kept, else its subject;
          # intent new takes a title as its subject and keeps the id in its facts.
          RUNS_SQL = <<~SQL
            SELECT updated_at AS at, COALESCE(json_extract(facts, '$.intent_id'), NULLIF(subject, '')) AS intent_id
            FROM routine_runs WHERE store = :store AND session_id = :session_id
          SQL

          SAVES_SQL = "SELECT at, intent_id FROM savepoints WHERE origin_id = :origin AND session_id = :session_id"

          def self.latest_first(rows)
            pairs = rows.filter_map { |row| row.values_at("at", "intent_id") if row["intent_id"] }
            pairs.sort_by { |at, _id| at.to_s }.reverse.map(&:last).uniq
          end

          def initialize(databases, store:, origin:)
            @databases = databases
            @store = store
            @origin = origin
          end

          def call(session_id)
            runs = @databases.fetch(:local).rows(RUNS_SQL, store: @store, session_id:)
            Touched.latest_first(runs + @databases.fetch(:work).rows(SAVES_SQL, origin: @origin.id, session_id:))
          end
        end
      end
    end
  end
end
