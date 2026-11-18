# frozen_string_literal: true

require_relative "print"

module Plastic
  module Graph
    module Prints
      # A part of store/index.json with a path and a digest of its own. Its print records a row and writes no file:
      # the index print writes the bytes.
      class Part < Print
        def level?(_folder) = true

        def write_to(_folder) = nil
      end
    end
  end
end
