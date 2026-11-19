# frozen_string_literal: true

require_relative "sync_selection"

module Plastic
  module Graph
    module Knowledge
      # How a store's sync and import behave on this machine: which files of an
      # intent folder it reads, and whether an import removes the files it read.
      SyncSettings = Data.define(:selection, :remove_after_import) do
        def self.none = new(selection: SyncSelection.none, remove_after_import: false)

        # The same settings, with the recorded reports read from the store `database`.
        def for_store(database) = with(selection: selection.for_store(database))
      end
    end
  end
end
