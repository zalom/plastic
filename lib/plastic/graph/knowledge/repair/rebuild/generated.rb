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
            HEAD = 3

            # A generator writes its marker in the first lines; the same words quoted further down are text.
            def self.call(text) = text.strip.empty? || text.lines.first(HEAD).any? { |line| MARKERS.any? { |marker| line.include?(marker) } }
          end
        end
      end
    end
  end
end
