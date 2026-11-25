# frozen_string_literal: true

require_relative "../../../layout"
require_relative "../sync_selection"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Where a file of an intent folder belongs in the layout. `rel` is the path inside the intent folder; the
        # answer is the path inside it too, or nil when the file stays where it is: a core file, a file already in a
        # resources folder, machine state, or a file of an older layout that the repair removes or amends. A file of an
        # older layout that the layout moves or renames goes where its entry says. A file under resources/ is sorted by its
        # type: Markdown, HTML and scratch go to the tmp folder, since the reports folder holds only a recorded report or
        # one the setting reports.mandatory names. Any other file the layout does not allow goes whole to the tmp folder.
        module Classification
          def self.destination(rel)
            return if kept?(rel)

            Layout.destination(rel) || under_resources(rel) || "#{Layout.resource(:tmp)}#{rel}"
          end

          def self.kept?(rel) = Layout.core?(rel) || Layout.sorted?(rel) || machine?(rel) || stays?(rel)

          def self.machine?(rel) = Layout.machine?(rel)

          # A file of an older layout that its entry repairs in another way than by moving it.
          def self.stays?(rel) = !Layout.legacy_for(rel).nil? && Layout.destination(rel).nil?

          def self.under_resources(rel)
            inside = rel.delete_prefix(Layout.output_root).delete_prefix("#{Layout.resources_root}/")
            by_type(inside) unless inside == rel
          end

          def self.by_type(rel)
            return "#{Layout.resource(:tmp)}#{rel}" if rel.match?(Layout.scratch) || Layout.tmp_types.include?(SyncSelection.type_of(rel))

            "#{Layout.resource(:files)}#{rel}"
          end
        end
      end
    end
  end
end
