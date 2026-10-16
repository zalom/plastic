# frozen_string_literal: true

require "cgi"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        module Text
          # Removes markup while leaving visual separators and decoded entities.
          module MarkupText
            PATTERN = /<(script|style)\b.*?<\/\1>|<[^>]+>|&(?:#\d+|#x[0-9a-f]+|[a-z]+);/mi

            module_function

            def extract(source)
              TokenStream.new(source, PATTERN).extract { |match| token(match[0]) }
            end

            def token(value) = value.start_with?("&") ? CGI.unescapeHTML(value) : " "
          end
        end
      end
    end
  end
end
