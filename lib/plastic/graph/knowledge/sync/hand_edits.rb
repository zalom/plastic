# frozen_string_literal: true

require_relative "entry"
require_relative "readability"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The printed files a person edited, for the prints a command declares. A path with no row to print is left alone.
        class HandEdits
          def initialize(retrieval, folder, databases, kinds, facts)
            @retrieval = retrieval
            @folder = folder
            @databases = databases
            @kinds = kinds
            @facts = facts
          end

          # Each hand edited path with the reason sync up cannot read it, or nil when it can or when sync up prints it again.
          def call
            printed = @retrieval.printed
            edited = prints.select { |print| hand_edited?(print, printed) }.map(&:path)
            unreadable = Readability.new(@folder, @retrieval, @databases).call(edited.reject { |path| Entry.view?(path) || (Entry.generated?(path) && !printed[path]) })
            edited.to_h { |path| [path, unreadable[path]] }
          end

          private

          def hand_edited?(print, printed)
            path = print.path
            Entry.for(@folder, path, printed[path], print).hand_edited?
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
