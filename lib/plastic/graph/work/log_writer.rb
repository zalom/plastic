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

        def line(intent_id, kind, text, **parts)
          body = parts[:body]
          top = store.row(TOP_SQL, intent_id:).fetch("top")
          store.transaction do |batch|
            batch.put(:work_log, { intent_id:, position: top + 1, at: stamp, phase: "", node: parts.fetch(:node, ""), session_id: @writers.session, kind:, path: parts.fetch(:path, ""),
                                   sha256: body ? Digest::SHA256.hexdigest(body) : "", text:, origin_id: @writers.retrieval.origin_id })
          end
        end

        private

        def store = @writers.databases.fetch(:store)

        def stamp = Plastic.timestamp(@writers.clock.now)
      end
    end
  end
end
