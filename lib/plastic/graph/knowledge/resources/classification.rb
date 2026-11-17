# frozen_string_literal: true

require_relative "../sync_selection"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Where a file of an intent folder belongs in the resources layout. `rel` is the path inside the
        # intent folder; the answer is the path inside it too, or nil when the file stays where it is: a note,
        # a legacy file, machine state or a file already in a sorted folder. A file directly under
        # resources/output/ is sorted by its type.
        module Classification
          SORTED = %w[resources/output/reports/ resources/output/files/ resources/references/ resources/tmp/].freeze
          REFERENCES = { "references/" => "resources/references/", "resources/sources/" => "resources/references/sources/" }.freeze
          REPORT_FOLDERS = %w[reviews/ packets/ nodes/].freeze
          MACHINE = /\A(?:.*\.lock|\.DS_Store)\z/
          SCRATCH = /\.(?:last|out|tmp)\z/

          def self.destination(rel)
            return if kept?(rel)

            reference(rel) || report(rel) || by_type(rel.delete_prefix("resources/output/").delete_prefix("resources/"))
          end

          def self.kept?(rel) = SyncSelection.note?(rel) || SORTED.any? { |folder| rel.start_with?(folder) } || File.basename(rel).match?(MACHINE)

          def self.reference(rel)
            folder = REFERENCES.keys.find { |prefix| rel.start_with?(prefix) }
            folder && rel.sub(folder, REFERENCES.fetch(folder))
          end

          def self.report(rel) = ("resources/output/reports/#{rel}" if REPORT_FOLDERS.any? { |folder| rel.start_with?(folder) })

          def self.by_type(rel)
            return "resources/tmp/#{rel}" if rel.match?(SCRATCH)

            "resources/output/#{%w[md html].include?(SyncSelection.type_of(rel)) ? "reports" : "files"}/#{rel}"
          end
        end
      end
    end
  end
end
