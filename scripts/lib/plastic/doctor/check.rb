# frozen_string_literal: true

module Plastic
  module Doctor
    Check = Data.define(:label, :value, :repair) do
      def self.ok(label, detail) = new(label, "ok, #{detail}", nil)

      def self.finding(label, text, repair) = new(label, text, repair)

      def self.from(part)
        label, value, repair = part.to_h.values_at(:label, :value, :repair)
        repair ? finding(label, value, repair) : ok(label, value)
      end

      def judged(problem) = problem ? with(value: problem) : with(value: "ok, #{value}", repair: nil)

      def to_a = [label, value, repair]
    end
  end
end
