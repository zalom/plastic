# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Evidence
        module Text
          # Retains every character and its originating source line for plain text.
          module PlainText
            module_function

            def extract(source) = Extraction.new(source, SourceLines.for(source))
          end
        end
      end
    end
  end
end
