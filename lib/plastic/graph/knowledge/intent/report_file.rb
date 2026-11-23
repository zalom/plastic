# frozen_string_literal: true

require_relative "../reports"
require_relative "../sync_selection"
require_relative "outcome_section"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # One report of an intent: the intent that holds it and its path under resources/output/reports/. The intent and
        # the path travel together, so the Reporter takes one value, not two.
        class ReportFile < Data.define(:intent, :path)
          MANDATORY = "mandatory"

          def id = intent.intent_id

          # The file, relative to the store folder.
          def file = "#{intent.dir}/#{path}"

          # `- PATH`, or `- PATH (mandatory)` for a report the setting names.
          def line(text) = "- #{path} (#{text})".delete_suffix(" ()")

          # The outcome with this path listed once, in the form `text` names, or nil when the outcome lists it so already.
          # The line of the other form of the setting is replaced, and an older line with other words stays.
          def outcome(body, text, heading)
            wanted = line(text)
            return if body.lines.map(&:chomp).include?(wanted)

            OutcomeSection.for(without_stale(body, wanted), heading).add(wanted)
          end

          # Why the file cannot be recorded, or nil: the questions the sync asks of `selection` before it reads a file
          # into documents, and the resolved file stays inside the reports folder of the intent.
          def problem(selection, folder)
            Reports.path_problem(path) || type_problem(selection) || file_problem(folder) ||
              ("#{path} is not text; the sync keeps it as an attachment, not as a report" unless text?(folder))
          end

          # The bytes of the file.
          def body(folder) = folder.read(file).force_encoding(Encoding::UTF_8)

          private

          # The outcome with the line of the other form of the setting taken out, and the blank lines it leaves at the end.
          def without_stale(body, wanted)
            stale = [line(""), line(MANDATORY)] - [wanted]
            lines = body.lines
            kept = lines.reject { |each| stale.include?(each.chomp) }
            (kept.size == lines.size) ? body : "#{kept.join.rstrip}\n"
          end

          def type_problem(selection)
            "the sync does not read .#{SyncSelection.type_of(path)} files; #{path} cannot be a report" unless selection.reads_type?(path)
          end

          def file_problem(folder)
            return "no file #{file}" unless folder.exist?(file)

            "#{path} leads outside #{intent.dir}/#{Reports::FOLDER}" unless inside?(folder)
          end

          # Whether the file, with every link resolved, is still inside the reports folder of the intent.
          def inside?(folder) = folder.real(file).start_with?("#{folder.real("#{intent.dir}/#{Reports::FOLDER}")}/")

          def text?(folder) = Retrieval::Evidence::Text.classify(path, folder.read(file)) == :text
        end
      end
    end
  end
end
