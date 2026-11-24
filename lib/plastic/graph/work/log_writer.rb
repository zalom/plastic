# frozen_string_literal: true

require "digest"

module Plastic
  module Graph
    module Work
      # Writes the work log lines of the logged writes, each in the transaction of the write it records.
      class LogWriter
        TOP_SQL = "SELECT COALESCE(MAX(position), 0) AS top FROM work_log WHERE intent_id = :intent_id"

        def initialize(writers)
          @writers = writers
        end

        def recorded(&) = store.atomically(&)

        def logged(intent_id, kind, wording)
          recorded { yield.tap { |moved,| moved && line(intent_id, kind, wording) } }
        end

        # One line at the end of the intent's work log. `parts` may name the node, the path, the body whose hash the line
        # keeps, `at`, a stored time for a line that records an older event, and `old_text` and `new_text`, the exact old
        # and new text of a change to the text inside a file; the clock gives the time otherwise.
        def line(intent_id, kind, text, **parts)
          top = store.row(TOP_SQL, intent_id:).fetch("top")
          store.transaction do |batch|
            batch.put(:work_log, { intent_id:, position: top + 1, phase: "", session_id: @writers.session, kind:, text:, origin_id: @writers.retrieval.origin_id, **written(parts) })
          end
        end

        private

        # The fields of the line that `parts` gives: its time, node, path, the hash of its body and any old and new text.
        def written(parts)
          body = parts[:body]
          { at: parts.fetch(:at) { stamp }, node: parts.fetch(:node, ""), path: parts.fetch(:path, ""), sha256: body ? Digest::SHA256.hexdigest(body) : "",
            **parts.slice(:old_text, :new_text) }
        end

        def store = @writers.databases.fetch(:store)

        def stamp = Plastic.timestamp(@writers.clock.now)
      end
    end
  end
end
