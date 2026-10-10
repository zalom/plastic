# frozen_string_literal: true

module CommandReference
  # One wire of a chain, with the outcomes it carries.
  Edge = Data.define(:from, :to, :outcomes) do
    def words = outcomes.compact.map { |name| ":#{name}" }.join(" ").then { |text| text.empty? ? "every outcome" : text }
  end
end
