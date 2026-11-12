# frozen_string_literal: true

module Plastic
  module Graph
    # Shared by every record the graphs store. A record is an immutable Data
    # value built from a row, and a graph writes it back as a row.
    module Record
      def self.included(base) = base.extend(ClassMethods)

      # Builds a record from a row or a parsed JSON hash.
      module ClassMethods
        # Unknown keys are dropped and missing keys read as nil, so an older
        # row or file still loads.
        def from_h(hash)
          values = hash.transform_keys(&:to_sym)
          new(**members.to_h { |member| [member, values[member]] })
        end
      end
    end
  end
end
