# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # How rulings are ordered: by the number of their decision, each addition after its decision, as D1, D1.1, D1.2, D2.
      # The brief and the node packet both read it here.
      module RulingOrder
        # The rulings by their number, oldest first.
        def self.sorted(rulings) = rulings.sort_by { |ruling| ruling.id.scan(/\d+/).map(&:to_i) }

        # The additions of the whole decision `id`, such as D1.1 and D1.2 of D1, in order.
        def self.additions(rulings, id) = sorted(rulings.select { |ruling| ruling.id.start_with?("#{id}.") })
      end
    end
  end
end
