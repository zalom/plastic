# frozen_string_literal: true

require_relative "../../layout"

module Plastic
  module Graph
    module Knowledge
      # Decides which files of an intent folder are legacy data: the ones the layout reads into legacy rows,
      # such as the plan, the checklist and the action files. `rel` is the path inside the intent folder.
      module LegacyPath
        def self.legacy?(rel) = Layout.legacy_sync(rel) == "legacy_rows"
      end
    end
  end
end
