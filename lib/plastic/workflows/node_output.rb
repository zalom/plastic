# frozen_string_literal: true

require "json"

module Plastic
  module Workflows
    # The JSON a worker hands to `node done --output PATH`: read as the file holds it, and checked to be JSON.
    # Plastic checks that the text parses; the worker's harness checks it against the node's schema.
    module NodeOutput
      module_function

      # The text of the file and nil, or nil and the reason the file cannot be the output of a node.
      def read(path)
        text = File.binread(path).force_encoding(Encoding::UTF_8)
        JSON.parse(text)
        [text, nil]
      rescue SystemCallError => e
        [nil, "the output file cannot be read: #{e.message}"]
      rescue JSON::ParserError, EncodingError => e
        [nil, "the output file #{path} is not JSON: #{e.message.lines.first.to_s.strip}"]
      end
    end
  end
end
