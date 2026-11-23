# frozen_string_literal: true

require_relative "../knowledge/intent/reporter"

module Plastic
  module Graph
    module Work
      # The writes of what an intent keeps beside its goal (rulings, verdicts, notes, reports, amendments), each leaving
      # its work log line.
      class LoggedRecords
        def initialize(writers, log)
          @writers = writers
          @log = log
        end

        def add_ruling(intent_id:, **fields)
          @log.recorded do
            @writers.rulings.add_ruling(intent_id:, **fields).tap { |ruling| ruling && @log.line(intent_id, "ruled", "#{ruling.id} #{ruling.text}") }
          end
        end

        def add_verdict(intent_id:, **fields)
          @log.recorded do
            @writers.verdicts.add_verdict(intent_id:, **fields).tap do |verdict|
              verdict && @log.line(intent_id, "verdict", "round #{verdict.round} #{verdict.verdict}: #{verdict.findings}")
            end
          end
        end

        def note_intent(intent, kind, text)
          intent_id = intent.intent_id
          @log.recorded do
            noter.write(intent, kind, text).tap do
              @log.line(intent_id, "noted", "#{kind}: #{text}", path: Knowledge::Intent::Noter::FILE,
                body: @writers.retrieval.fetch(intent_id, Knowledge::Intent::Noter::FILE).body)
            end
          end
        end

        # Writes the `amended` lines of the links that the resource sort rewrote in the core files of closed intents, all in
        # one transaction.
        def amend_intents(amendments)
          @log.recorded { amendments.each { |amendment| amendment.write(@log) } }
        end

        # Records a report, a ReportFile; `text` is Reporter::MANDATORY for a report the setting names, else empty.
        def report_intent(report, text)
          @log.recorded do
            reporter.record(report, text).tap do
              @log.line(report.id, "reported", text, path: report.path, body: report.body(@writers.folder))
            end
          end
        end

        def reporter = (@reporter ||= Knowledge::Intent::Reporter.new(@writers.databases, @writers.retrieval, @writers.folder))

        private

        def noter = (@noter ||= Knowledge::Intent::Noter.new(@writers.databases, @writers.retrieval))
      end
    end
  end
end
