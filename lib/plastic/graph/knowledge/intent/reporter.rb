# frozen_string_literal: true

require "digest"
require_relative "outcome_section"
require_relative "../reports"
require_relative "../sync_selection"
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
          RECORDED = "SELECT 1 FROM work_log WHERE kind = 'reported' AND intent_id = :intent_id AND path = :path"

          def initialize(databases, retrieval, folder)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
          end

          # Why `path` of `intent` cannot be recorded, or nil: the same questions the sync asks of `selection` before it
          # reads a file into documents, and the resolved file stays inside the reports folder of the intent.
          def problem(intent, path, selection)
            Reports.path_problem(path) || type_problem(path, selection) || file_problem(intent.dir, path) ||
              ("#{path} is not text; the sync keeps it as an attachment, not as a report" unless text?(intent, path))
          end

          # A `reported` line of any origin counts, as it does for the sync (Reports::RECORDED).
          def recorded?(intent_id, path) = !store.row(RECORDED, intent_id:, path:).nil?

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

          def type_problem(path, selection)
            "the sync does not read .#{SyncSelection.type_of(path)} files; #{path} cannot be a report" unless selection.reads_type?(path)
          end

          def file_problem(dir, path)
            return "no file #{dir}/#{path}" unless @folder.exist?("#{dir}/#{path}")

            "#{path} leads outside #{dir}/#{Reports::FOLDER}" unless inside?(dir, path)
          end

          # Whether the file, with every link resolved, is still inside the reports folder of the intent.
          def inside?(dir, path) = real("#{dir}/#{path}").start_with?("#{real("#{dir}/#{Reports::FOLDER}")}/")

          def real(rel) = File.realpath(@folder.path(rel))

          def text?(intent, path) = Retrieval::Evidence::Text.classify(path, @folder.read("#{intent.dir}/#{path}")) == :text

          def line(path, asked) = (asked == MANDATORY) ? "- #{path} (#{MANDATORY})" : "- #{path}, asked: #{asked.inspect}"

          def store = @databases.fetch(:store)

          def writer = Retrieval::Evidence::Writer.new(store, @retrieval.origin_id, clock: @retrieval.clock)
        end
      end
    end
  end
end
