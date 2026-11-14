# frozen_string_literal: true

require_relative "entry"

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

          def call
            printed = @retrieval.printed
            prints.select { |print| hand_edited?(print, printed) }.map(&:path)
          end

          private

          def hand_edited?(print, printed)
            path = print.path
            Entry.new(path, @folder.digest(path), printed[path], print).hand_edited?
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
