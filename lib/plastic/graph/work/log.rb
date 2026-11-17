# frozen_string_literal: true

require "digest"
require_relative "log_line"

module Plastic
  module Graph
    module Work
      # Appends the lines of an intent's work log. The owning rows are stored first; the line
      # goes in a second transaction, and the next write to the intent adds a line a failed
      # write left out. An intent converted from savepoints is never given an `opened` line.
      class Log
        Missing = Data.define(:kind, :at, :text)

        def initialize(databases, retrieval, session:)
          @databases = databases
          @retrieval = retrieval
          @session = session
        end

        def record(intent_id, kind, text, **parts)
          repair(intent_id)
          put(intent_id, [line(kind, text, **parts)])
        end

        def repair(intent_id)
          found = missing(intent_id)
          put(intent_id, found.map { |line| { **line.to_h, node: "", path: "", sha256: "" } })
        end

        private

        def line(kind, text, node: "", path: "", body: nil)
          { kind:, at: Plastic.now, text:, node:, path:, sha256: (Digest::SHA256.hexdigest(body) if body).to_s }
        end

        def put(intent_id, lines)
          return 0 if lines.empty?

          start = @retrieval.work_log(intent_id).map(&:position).max.to_i
          rows = lines.each_with_index.map { |line, index| { intent_id:, position: start + index + 1, phase: "", session_id: @session, **line } }
          @databases.fetch(:work).transaction { |batch| batch.put_all(:work_log, rows) }
          rows.size
        end

        def missing(intent_id)
          intent = @retrieval.intent(intent_id)
          have = @retrieval.work_log(intent_id)
          return [] unless intent

          expected(intent, have).reject { |line| have.any? { |row| row.kind == line.kind } }
        end

        def expected(intent, have)
          [
            (Missing.new("opened", intent.opened_at, "Opened: #{intent.title}") if have.empty?),
            *approved(intent), *closed(intent)
          ].compact
        end

        def approved(intent)
          approval = @retrieval.approval(intent.intent_id)
          approval && Missing.new("approved", approval.at, "Go-ahead given")
        end

        def closed(intent)
          return Missing.new("abandoned", intent.closed_at, "Abandoned: #{intent.disposition}") if intent.status == "abandoned"

          completion = @retrieval.completions(intent.intent_id).first
          completion && Missing.new("done", completion.at, "Done")
        end
      end
    end
  end
end
