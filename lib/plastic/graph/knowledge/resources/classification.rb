# frozen_string_literal: true

require_relative "../../../layout"
require_relative "../sync_selection"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Where a file of an intent folder belongs in the resources layout. `rel` is the path inside the
        # intent folder; the answer is the path inside it too, or nil when the file stays where it is: a core
        # file, a file of an older layout that the layout keeps in place, machine state or a file already in a
        # sorted folder. A file of an older layout that the layout moves goes where its entry says. A file
        # directly under resources/output/ is sorted by its type. Loose Markdown and HTML files and scratch go to
        # the tmp folder, since the reports folder holds only a recorded report or one the setting
        # reports.mandatory names.
        module Classification
          def self.destination(rel)
            return if kept?(rel)

            Layout.destination(rel) || by_type(rel.delete_prefix(Layout.output_root).delete_prefix("#{Layout.resources_root}/"))
          end

          def self.kept?(rel) = SyncSelection.note?(rel) || Layout.sorted?(rel) || machine?(rel) || stays?(rel)

          def self.machine?(rel) = Layout.machine?(rel)

          # A file of an older layout that its entry repairs in another way than by moving it.
          def self.stays?(rel) = !Layout.legacy_for(rel).nil? && Layout.destination(rel).nil?

          def self.by_type(rel)
            return "#{Layout.resource(:tmp)}#{rel}" if rel.match?(Layout.scratch) || Layout.tmp_types.include?(SyncSelection.type_of(rel))

            "#{Layout.resource(:files)}#{rel}"
          end
        end
      end
    end
  end
end
