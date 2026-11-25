# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # Tells whether an old file holds no data: an empty file, a placeholder a template wrote, or a stub that an
          # older end-intent backfilled from the record.
          module Generated
            MARKERS = ["<!-- plastic:placeholder -->", "backfilled from the record by end-intent"].freeze

            def self.call(text) = text.strip.empty? || MARKERS.any? { |marker| text.include?(marker) }
          end
        end
      end
    end
  end
end
