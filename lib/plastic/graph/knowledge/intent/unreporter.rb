# frozen_string_literal: true

require "fileutils"
require_relative "reporter"
require_relative "../reports"
require_relative "../repair/removal"
require_relative "../resources/row_moves"
require_relative "../../evidence/writer"
require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # Removes one report of an intent that was recorded by mistake: the rows that hold it (its documents, its head
        # and its printed record), its line under Reports in the outcome, and its file, which is deleted or moved to
        # resources/tmp/. The `removed` work log line, and the `amended` line of a closed intent, are written by
        # Work::LoggedRecords.
        class Unreporter
          FILE = Reporter::FILE
          HEADING = Reporter::HEADING
          TMP = Layout.resource(:tmp)
          CLOSED = %w[done abandoned].freeze

          # What one removal did: the report, the outcome it left, nil when the outcome did not list the report, and the
          # path the file moved to inside the intent folder, nil when it was deleted.
          Removed = Data.define(:report, :outcome, :moved) do
            def words = moved ? "moved: #{report.path} to #{moved}" : "removed: #{report.path}"

            # Whether the removal changed the outcome of an intent that is done or abandoned.
            def amends? = !outcome.nil? && CLOSED.include?(report.intent.status)

            # The text of the `amended` line: the file, the report and the reason the layout gives.
            def amendment = "#{FILE}: report #{report.path} removed; #{Layout.amendment_reason(:report)}"
          end

          # Where `--to-tmp` moves the report, inside the intent folder: its path under resources/tmp/.
          def self.moved(report) = "#{TMP}#{report.path.delete_prefix(Reports::FOLDER)}"

          def initialize(databases, retrieval, folder)
            @databases = databases
            @retrieval = retrieval
            @folder = folder
          end

          # Why the report cannot be removed, or nil: it has no record that counts, or `to_tmp` would move it onto a file.
          def problem(report, to_tmp)
            return "#{report.path} is no recorded report of intent #{report.id}; nothing to remove" unless recorded?(report)

            target = "#{report.intent.dir}/#{Unreporter.moved(report)}"
            "#{target} already exists; move or remove it first" if to_tmp && @folder.exist?(target)
          end

          # Drops the rows of the report, takes it out of the outcome and deletes its file, or moves it when `to_tmp`.
          def remove(report, to_tmp)
            Resources::RowMoves.new(store).drop([Repair::Removal.new(report.file)])
            outcome = unlist(report)
            Removed.new(report, outcome, to_tmp ? move(report) : delete(report))
          end

          private

          def recorded?(report) = Reports.none.recorded_from(store).recorded?(report.id, report.path)

          # Writes the outcome without the line of the report; returns the new outcome, or nil when it did not list it.
          def unlist(report)
            id = report.id
            report.unlisted(@retrieval.fetch(id, FILE)&.body.to_s, HEADING).tap { |body| body && writer.write(id, FILE, body) }
          end

          def move(report)
            return unless @folder.exist?(report.file)

            target = Unreporter.moved(report)
            to = @folder.path("#{report.intent.dir}/#{target}")
            FileUtils.mkdir_p(File.dirname(to))
            File.rename(@folder.path(report.file), to)
            target
          end

          def delete(report) = @folder.delete(report.file).then { nil }

          def store = @databases.fetch(:store)

          def writer = Retrieval::Evidence::Writer.new(store, @retrieval.origin_id, clock: @retrieval.clock)
        end
      end
    end
  end
end
