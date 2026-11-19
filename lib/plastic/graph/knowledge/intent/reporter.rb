# frozen_string_literal: true

require "digest"
require_relative "outcome_section"
require_relative "../reports"
require_relative "../../evidence/writer"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Records one report of an intent, a file in resources/output/reports/ that the owner asked for or the setting
        # reports.mandatory names: its row in documents, so the sync reads it, and its line under Reports in the outcome.
        # The `reported` work log line that holds the record is written by Work::LoggedWrites.
        class Reporter
          FILE = "outcome.md"
          HEADING = "## Reports"
          MANDATORY = "mandatory"
          RECORDED = "SELECT 1 FROM work_log WHERE kind = 'reported' AND intent_id = :intent_id AND path = :path AND origin_id = :origin"

          def initialize(databases, retrieval, folder)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
          end

          # Why `path` of `intent` cannot be recorded, or nil.
          def problem(intent, path)
            return "#{path} is not in #{Reports::FOLDER}; a report lives there" unless Reports.report?(path)

            "no file #{intent.dir}/#{path}" unless @folder.exist?("#{intent.dir}/#{path}")
          end

          def recorded?(intent_id, path) = !store.row(RECORDED, intent_id:, path:, origin: @retrieval.origin_id).nil?

          # The bytes of the report, for the sha256 of its log line.
          def body(intent, path) = @folder.read("#{intent.dir}/#{path}").force_encoding(Encoding::UTF_8)

          # Writes the report row and the outcome line; `asked` is the owner's words, or MANDATORY.
          def write(intent, path, asked)
            id = intent.intent_id
            writer.write(id, path, body(intent, path))
            writer.write(id, FILE, OutcomeSection.for(@retrieval.fetch(id, FILE)&.body, HEADING).add(line(path, asked)))
            @retrieval.reference(id, path).fetch(:uri)
          end

          private

          def line(path, asked) = (asked == MANDATORY) ? "- #{path} (#{MANDATORY})" : "- #{path}, asked: #{asked.inspect}"

          def store = @databases.fetch(:store)

          def writer = Retrieval::Evidence::Writer.new(store, @retrieval.origin_id, clock: @retrieval.clock)
        end
      end
    end
  end
end
