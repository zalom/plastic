# frozen_string_literal: true

require_relative "../prints"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The prints a command declares: the kinds of file it writes and the facts that name the intent or the roadmap.
        # A path with no row to print has no print.
        class DeclaredPrints
          def initialize(retrieval, kinds, facts)
            @retrieval = retrieval
            @kinds = kinds
            @facts = facts
          end

          def call
            [*index_prints, *intent_prints, *roadmap_prints].uniq(&:path)
          end

          private

          def index_prints = @kinds.all?(:roadmap) ? [] : [Prints.index(@retrieval)]

          def intent_prints
            intent_id = @facts[:intent_id] || @facts[:id]
            row = intent_id && @kinds.include?(:intent) && @retrieval.intent(intent_id)
            row ? Prints.of_intent(@retrieval, row) : []
          end

          def roadmap_prints
            slug = @facts[:slug]
            (@kinds.include?(:roadmap) && slug && @retrieval.roadmaps.find(slug)) ? [Prints.roadmap(@retrieval, slug)] : []
          end
        end
      end
    end
  end
end
