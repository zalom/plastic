# frozen_string_literal: true

require_relative "entry"
require_relative "readability"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The printed files a person edited, for the prints a command declares. A core file that no row holds is edited
        # when it is on disk; no rows print it again, so it gets no reason and sync up says why it cannot read it.
        class HandEdits
          def initialize(retrieval, folder, databases, prints)
            @retrieval = retrieval
            @folder = folder
            @databases = databases
            @prints = prints
          end

          # Each hand edited path with the reason sync up cannot read it, or nil when it can or when sync up prints it again.
          def call
            printed = @retrieval.stored.printed
            edited = @prints.select { |print| hand_edited?(print, printed) }
            unreadable = Readability.new(@folder, @retrieval, @databases).call(reprintable(edited, printed))
            edited.to_h { |print| [print.path, unreadable[print.path]] }
          end

          private

          # The edited paths whose rows print them again: not a core file that no row holds, nor an index this home never printed.
          def reprintable(edited, printed)
            edited.select(&:sha256).map(&:path).reject { |path| path == StoreFolder::INDEX && !printed[path] }
          end

          def hand_edited?(print, printed)
            path = print.path
            Entry.for(@folder, path, printed[path], print).hand_edited?
          end
        end
      end
    end
  end
end
