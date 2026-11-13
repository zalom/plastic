# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Reader
        class GraphFile
          # Words for a value a graph file may leave out, so a person never reads Ruby's nil.
          module Wording
            def self.intent(named) = of(named, "no intent") { |intent| "intent #{intent.inspect}" }

            def self.state(state) = of(state, "with no state") { |named| "in the unknown state #{named.inspect}" }

            def self.edge(name) = of(name, "with no end") { |end_name| "to #{end_name.inspect}, which is no node it holds" }

            def self.of(value, missing) = [value].compact.map { |present| yield(present) }.first || missing
          end
        end
      end
    end
  end
end
