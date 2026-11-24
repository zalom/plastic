# frozen_string_literal: true

require_relative "../prints"
require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The prints a command declares: the kinds of file it writes and the facts that name the intent.
        # A core file of the intent with no row to print has a print of nothing, so a file that no row holds counts as
        # written by hand: the next print would build it from empty rows. Any other path with no row has no print.
        class DeclaredPrints
          # The print of a core file that no row holds.
          UNROWED = ->(path) { Prints::Print.new(path, nil, nil) }

          # `prints` of the intent folder `dir`, and the print of nothing for each core file they leave out.
          def self.with_unrowed(dir, prints)
            printed = prints.map(&:path)
            [*prints, *Layout.core_names.map { |name| "#{dir}/#{name}" }.reject { |path| printed.include?(path) }.map(&UNROWED)]
          end

          def initialize(retrieval, kinds, facts)
            @retrieval = retrieval
            @kinds = kinds
            @facts = facts
          end

          def call
            [*index_prints, *intent_prints].uniq(&:path)
          end

          private

          def index_prints = [Prints.index(@retrieval)]

          def intent_prints
            intent_id = @facts[:intent_id] || @facts[:id]
            row = intent_id && @kinds.include?(:intent) && @retrieval.intent(intent_id)
            row ? self.class.with_unrowed(row.dir, Prints.of_intent(@retrieval, row)) : []
          end
        end
      end
    end
  end
end
