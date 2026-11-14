# frozen_string_literal: true

require_relative "entry_files"
require_relative "readability"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The printed files a person edited, for the prints a command declares. A path with no row to print is left alone.
        class HandEdits
          def initialize(retrieval, folder, kinds, facts)
            @retrieval = retrieval
            @folder = folder
            @kinds = kinds
            @facts = facts
          end

          # Each hand edited path with the reason sync up cannot read it, or nil when it can.
          def call
            edited = edited_paths
            unreadable = Readability.new(@folder, @retrieval).call(edited.reject { |path| Entry.generated?(path) })
            edited.to_h { |path| [path, unreadable[path]] }
          end

          private

          def edited_paths
            printed = @retrieval.printed
            prints.select { |print| hand_edited?(print, printed) }.map(&:path)
          end

          def hand_edited?(print, printed)
            path = print.path
            EntryFiles.new(@folder).entry(path, printed[path], print).hand_edited?
          end

          def prints = [*index_prints, *intent_prints, *roadmap_prints].uniq(&:path)

          def index_prints = @kinds.all?(:roadmap) ? [] : [Prints.index(@retrieval)]

          def intent_prints
            intent_id = @facts[:intent_id] || @facts[:id]
            row = intent_id && @kinds.include?(:intent) && @retrieval.intent(intent_id)
            row ? Prints.of_intent(@retrieval, row) : []
          end

          def roadmap_prints
            slug = @facts[:slug]
            (@kinds.include?(:roadmap) && slug && @retrieval.roadmap(slug)) ? [Prints.roadmap(@retrieval, slug)] : []
          end
        end
      end
    end
  end
end
