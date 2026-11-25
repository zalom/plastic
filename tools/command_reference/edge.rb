# frozen_string_literal: true

module CommandReference
  # One wire of a chain, with the outcomes it carries.
  Edge = Data.define(:from, :to, :outcomes) do
    def because(flows)
      carried = flows.fetch(from).outcomes.select { |outcome| outcomes.include?(outcome.name) }
      Words.angled(carried.map(&:because).join(" or "))
    end
  end
end
