# frozen_string_literal: true

require "set"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # The documents that held a head before a bulk write: only they can hold search rows to replace.
        class Heads
          # Stands for heads nobody read, so every document counts as known.
          class Unread
            def known?(_intent_id, _path) = true
          end

          def initialize(keys = Set.new)
            @keys = keys
          end

          def known?(intent_id, path)
            seen = @keys.include?([intent_id, path])
            @keys << [intent_id, path]
            seen
          end
        end
      end
    end
  end
end
