# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # How rulings are ordered and which of them another ruling supersedes. The brief marks the superseded
      # ones and the node packet leaves them out; both read it here.
      module RulingOrder
        # The rulings by their number, oldest first.
        def self.sorted(rulings) = rulings.sort_by { |ruling| ruling.id[/\d+/].to_i }

        # The ids that another ruling supersedes.
        def self.superseded_ids(rulings) = rulings.filter_map(&:supersedes).to_set

        # The sorted rulings that no other ruling supersedes.
        def self.in_force(rulings)
          superseded = superseded_ids(rulings)
          sorted(rulings).reject { |ruling| superseded.include?(ruling.id) }
        end
      end
    end
  end
end
