# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # Decides which files of an intent folder are legacy data: the plan, the checklist and
      # everything under actions/. `rel` is the path inside the intent folder.
      module LegacyPath
        FILES = %w[plan.md checklist.md].freeze
        FOLDER = "actions/"

        def self.legacy?(rel) = FILES.include?(rel) || rel.start_with?(FOLDER)
      end
    end
  end
end
