# frozen_string_literal: true

module Plastic
  module Graph
    module EvidenceText
      # Provides a source-line vector for extracted text and passage slicing.
      module SourceLines
        module_function

        def for(source)
          line = 1
          source.each_char.map do |character|
            current = line
            line += 1 if character == "\n"
            current
          end
        end
      end
    end
  end
end
