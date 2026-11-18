# frozen_string_literal: true

require_relative "sync_selection"

module Plastic
  module Graph
    module Knowledge
      # How a store's sync and import behave on this machine: which files of an
      # intent folder it reads, and whether an import removes the files it read.
      SyncSettings = Data.define(:selection, :remove_after_import) do
        def self.none = new(selection: SyncSelection.none, remove_after_import: false)
      end
    end
  end
end
