# frozen_string_literal: true

module Plastic
  module Graph
    # The next sequential id after the highest one already taken, numbered
    # under one prefix, such as n1 and n2 for nodes.
    module NextId
      def self.after(rows, prefix:)
        highest = rows.filter_map { |row| row.id[/\A#{prefix}(\d+)\z/, 1]&.to_i }.max || 0
        "#{prefix}#{highest + 1}"
      end
    end
  end
end
