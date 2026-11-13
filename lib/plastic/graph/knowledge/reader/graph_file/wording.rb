# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Reader
        class GraphFile
          # Words for a value a graph file may leave out, so a person never reads Ruby's nil.
          module Wording
            def self.of(value, missing) = [value].compact.map { |present| yield(present) }.first || missing
          end
        end
      end
    end
  end
end
