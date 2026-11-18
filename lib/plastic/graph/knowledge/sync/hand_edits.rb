# frozen_string_literal: true

require_relative "entry"
require_relative "readability"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The printed files a person edited, for the prints a command declares. A path with no row to print is left alone.
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
            edited = @prints.select { |print| hand_edited?(print, printed) }.map(&:path)
            unreadable = Readability.new(@folder, @retrieval, @databases).call(edited.reject { |path| path == StoreFolder::INDEX && !printed[path] })
            edited.to_h { |path| [path, unreadable[path]] }
          end

          private

          def hand_edited?(print, printed)
            path = print.path
            Entry.for(@folder, path, printed[path], print).hand_edited?
          end
        end
      end
    end
  end
end
