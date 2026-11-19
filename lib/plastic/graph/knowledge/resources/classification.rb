# frozen_string_literal: true

require_relative "../sync_selection"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Where a file of an intent folder belongs in the resources layout. `rel` is the path inside the
        # intent folder; the answer is the path inside it too, or nil when the file stays where it is: a note,
        # a legacy file, machine state or a file already in a sorted folder. A file directly under
        # resources/output/ is sorted by its type. Reviews, packets, node files, loose Markdown and HTML files and
        # scratch go to resources/tmp/, since resources/output/reports/ holds only a report the owner asked for or the
        # setting reports.mandatory names.
        module Classification
          SORTED = %w[resources/output/reports/ resources/output/files/ resources/references/ resources/tmp/].freeze
          REFERENCES = { "references/" => "resources/references/", "resources/sources/" => "resources/references/sources/" }.freeze
          TMP_FOLDERS = %w[reviews/ packets/ nodes/].freeze
          MACHINE = /\A(?:.*\.lock|\.DS_Store)\z/
          SCRATCH = /\.(?:last|out|tmp)\z/
          TMP_TYPES = %w[md html].freeze

          def self.destination(rel)
            return if kept?(rel)

            reference(rel) || tmp_folder(rel) || by_type(rel.delete_prefix("resources/output/").delete_prefix("resources/"))
          end

          def self.kept?(rel) = SyncSelection.note?(rel) || SORTED.any? { |folder| rel.start_with?(folder) } || machine?(rel)

          def self.machine?(rel) = File.basename(rel).match?(MACHINE)

          def self.reference(rel)
            folder = REFERENCES.keys.find { |prefix| rel.start_with?(prefix) }
            folder && rel.sub(folder, REFERENCES.fetch(folder))
          end

          def self.tmp_folder(rel) = ("resources/tmp/#{rel}" if TMP_FOLDERS.any? { |folder| rel.start_with?(folder) })

          def self.by_type(rel)
            return "resources/tmp/#{rel}" if rel.match?(SCRATCH) || TMP_TYPES.include?(SyncSelection.type_of(rel))

            "resources/output/files/#{rel}"
          end
        end
      end
    end
  end
end
