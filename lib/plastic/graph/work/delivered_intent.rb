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

        def initialize(stamp, label, retrieval)
          @stamp = stamp
          @label = label
          @retrieval = retrieval
        end

        # The moment it closed, for ordering across time zones.
        def moment = Plastic.utc(@stamp).to_s

        def to_row = ["delivered:", to_s]

        # The day a stored time falls on here; an older date-only value shows as it is.
        def to_s = [Plastic.local_day(@stamp) || @stamp.to_s[0, 10], @label, landing].compact.join(" ")

        private

        def landing
          found = LANDINGS.filter_map { |name| line(name) }.first
          "- #{found}" if found
        end

        def line(name) = outcome.values(name).first&.then { |value| "#{name}: #{value}" }

        def outcome = @outcome ||= Knowledge::Outcome.new(@retrieval, @label.split.first)
      end
    end
  end
end
