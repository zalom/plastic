# frozen_string_literal: true

require_relative "../../clock"
require_relative "../knowledge/outcome"

module Plastic
  module Graph
    module Work
      # One closed intent of a project digest: the day it closed, its label, and the line of its outcome.md that says how
      # it landed, `Merged:` or `Committed:`, when the outcome has one.
      class DeliveredIntent
        LANDINGS = %w[Merged Committed].freeze

        attr_reader :stamp

        def initialize(stamp, label, retrieval)
          @stamp = stamp
          @label = label
          @retrieval = retrieval
        end

        # The day a stored time falls on here; an older date-only value shows as it is.
        def to_s = [Plastic.local_day(@stamp) || @stamp.to_s[0, 10], @label, landing].compact.join(" ")

        private

        def landing
          outcome = Knowledge::Outcome.new(@retrieval, @label.split.first)
          found = LANDINGS.flat_map { |name| outcome.values(name).first(1).map { |value| "#{name}: #{value}" } }.first
          "- #{found}" if found
        end
      end
    end
  end
end
