# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      # Exposes node, work log, edge, and link reads through a retrieval graph.
      module StructureReads
        LOGGED_SQL = "SELECT intent_id FROM work_log WHERE session_id = :session AND origin_id = :origin ORDER BY at DESC, rowid DESC"
        LINKING_SQL = "SELECT * FROM links WHERE origin_id = :origin AND (to_ref = :id OR to_ref LIKE :prefix)"

        def work_log(intent_id = nil) = read(:work_log, intent_id)

        # The intents a session wrote lines to, the newest line first.
        def logged_intent_ids(session_id)
          @databases.fetch(:work).rows(LOGGED_SQL, session: session_id, origin: origin_id).map { |row| row.fetch("intent_id") }.uniq
        end

        def nodes(intent_id = nil) = read(:nodes, intent_id)
        def runs(intent_id = nil) = read(:runs, intent_id)
        def edges(intent_id = nil) = read(:edges, intent_id)
        def approvals(intent_id = nil) = read(:approvals, intent_id)
        def approval(intent_id) = approvals(intent_id).first
        def verdicts(intent_id = nil) = read(:verdicts, intent_id)
        def completions(intent_id = nil) = read(:completions, intent_id)
        def contexts(intent_id = nil) = read(:contexts, intent_id)
        def discoveries(intent_id = nil) = read(:discoveries, intent_id)

        def linking(id)
          @databases.fetch(:knowledge).rows(LINKING_SQL, origin: origin_id, id:, prefix: "#{id}/%").map { |row| Knowledge::Link.from_h(row) }
        end
      end
    end
  end
end
