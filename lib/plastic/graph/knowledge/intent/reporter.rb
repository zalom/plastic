# frozen_string_literal: true

require "digest"
require_relative "outcome_section"
require_relative "report_file"
require_relative "../reports"
require_relative "../sync_selection"
require_relative "../../evidence/writer"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Records one report of an intent, a file in resources/output/reports/: its row in documents, so the sync reads it,
        # and its line under Reports in the outcome.
        # The `reported` work log line that holds the record is written by Work::LoggedWrites.
        class Reporter
          FILE = "outcome.md"
          HEADING = "## Reports"
          MANDATORY = ReportFile::MANDATORY
          LATEST = "SELECT sha256 FROM work_log WHERE kind = 'reported' AND intent_id = :intent_id AND path = :path " \
                   "ORDER BY position DESC LIMIT 1"
          # What the record of a report says about the file now: :new, :changed or :unchanged, and the sha256 of the file.
          State = Data.define(:kind, :sha256) do
            # `latest` is the row of the latest `reported` line, or nil when there is none.
            def self.of(latest, digest)
              kind = latest.nil? ? :new : :changed
              kind = :unchanged if latest&.fetch("sha256") == digest
              new(kind, digest)
            end
          end

          def initialize(databases, retrieval, folder)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
          end

          # Why `path` of `intent` cannot be recorded, or nil: the same questions the sync asks of `selection` before it
          # reads a file into documents, and the resolved file stays inside the reports folder of the intent.
          def problem(report, selection) = report.problem(selection, @folder)

          # Compares the file with the latest `reported` line of any origin, as the sync counts them (Reports::RECORDED).
          def state(report)
            digest = Digest::SHA256.hexdigest(body(report))
            State.of(store.row(LATEST, intent_id: report.id, path: report.path), digest)
          end

          # The bytes of the report, for the sha256 of its log line.
          def body(report) = report.body(@folder)

          # Writes the report row and the outcome line; `text` is MANDATORY for a report the setting names, else empty.
          def write(report, text)
            id = report.id
            path = report.path
            writer.write(id, path, body(report))
            outcome(id, report, text)
            @retrieval.reference(id, path).fetch(:uri)
          end

          private

          # Puts the line of the report under Reports: a report recorded again keeps its one line, and the line of the path
          # with the other form of the setting is replaced, not left beside the new one.
          def outcome(id, report, text)
            updated = report.outcome(@retrieval.fetch(id, FILE)&.body.to_s, text, HEADING)
            writer.write(id, FILE, updated) if updated
          end

          def store = @databases.fetch(:store)

          def writer = Retrieval::Evidence::Writer.new(store, @retrieval.origin_id, clock: @retrieval.clock)
        end
      end
    end
  end
end
