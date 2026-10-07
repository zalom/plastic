# frozen_string_literal: true

module Plastic
  module Doctor
    Check = Data.define(:label, :value, :repair) do
      def self.ok(label, detail) = new(label, "ok, #{detail}", nil)

      def self.finding(label, text, repair) = new(label, text, repair)

      def self.of(label, problem, detail:, repair:) = problem ? finding(label, problem, repair) : ok(label, detail)

      def self.from(part) = of(part.label, part.repair && part.value, detail: part.value, repair: part.repair)

      def to_a = [label, value, repair]
    end
  end
end
