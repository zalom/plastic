# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        module Parse
          # The lines that continue one another into one text, with the number of the first.
          class Entry
            attr_reader :number

            def initialize(first, number)
              @parts = [first]
              @number = number
            end

            def add(text) = @parts << text

            def text = @parts.join(" ")
          end
        end
      end
    end
  end
end
