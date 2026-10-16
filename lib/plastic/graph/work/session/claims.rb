# frozen_string_literal: true

require_relative "../../lock"

module Plastic
  module Graph
    module Work
      class Session
        # The nodes of a lock's intent that the lock's session holds claimed,
        # as Lock::Claim values. A lock of another store reads no claims.
        class Claims
          SQL = %(SELECT id, updated_at FROM nodes WHERE intent_id = :intent_id AND state = 'claimed' AND "by" = :session_id ORDER BY id)

          def initialize(databases, store:)
            @databases = databases
            @store = store
          end

          def call(lock)
            lock => { store:, intent_id:, session_id: }
            return [] unless store == @store

            rows = @databases.fetch(:work).rows(SQL, intent_id: intent_id.to_s, session_id:)
            rows.map { |row| Lock::Claim.new(*row.values_at("id", "updated_at")) }
          end
        end
      end
    end
  end
end
