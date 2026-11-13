# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        module Parse
          # The lines of a roadmap file that could not be read, each naming the file and the line.
          class Problems
            def initialize(path)
              @path = path
              @messages = []
            end

            def add(message, number) = @messages << "#{@path}:#{number}: #{message}"

            def to_a = @messages
          end
        end
      end
    end
  end
end
