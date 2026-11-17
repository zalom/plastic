# frozen_string_literal: true

module CommandReference
  # One wire of a chain, with the outcomes it carries.
  Edge = Data.define(:from, :to, :outcomes) do
    def because(flows)
      carried = flows.fetch(from).outcomes.select { |outcome| outcomes.include?(outcome.name) }
      Words.angled(carried.map(&:because).join(" or "))
    end

    def words = outcomes.compact.map { |name| ":#{name}" }.join(" ").then { |text| text.empty? ? "every outcome" : text }
  end
end
