# frozen_string_literal: true

require "json"

module Plastic
  module Graph
    module Work
      # The output a done node stored: JSON text, or nothing. A hand-edited graph.json that is synced up can hold
      # text that is not JSON, so a reader asks before it parses.
      module StoredOutput
        # True when the node stored no output or stored JSON.
        def self.valid?(text)
          text.nil? || JSON.parse(text).then { true }
        rescue JSON::ParserError
          false
        end
      end
    end
  end
end
