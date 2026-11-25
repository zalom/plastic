# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      # How rulings are ordered: by the number of their decision, each addition after its decision, as D1, D1.1, D1.2, D2.
      # The brief and the node packet both read it here.
      module RulingOrder
        PARTS = /\AD(\d+)(?:\.(\d+))?/

        # The rulings by their number, oldest first.
        def self.sorted(rulings) = rulings.sort_by { |ruling| parts(ruling.id) }

        # The additions of the whole decision `id`, such as D1.1 and D1.2 of D1, in order.
        def self.additions(rulings, id) = sorted(rulings.select { |ruling| ruling.id.start_with?("#{id}.") })

        def self.parts(id) = id.match(PARTS)&.captures&.map(&:to_i) || [0, 0]
      end
    end
  end
end
