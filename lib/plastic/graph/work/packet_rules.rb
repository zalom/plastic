# frozen_string_literal: true

require_relative "../knowledge/ruling_order"
require_relative "../knowledge/spec"

module Plastic
  module Graph
    module Work
      # The rules a worker keeps beside its node: the intent's rulings and the constraints of its spec. Each list
      # holds LIMIT entries at most, the newest rulings and the first constraints; the rest is counted, and a line names the command that lists it.
      class PacketRules
        LIMIT = 20

        def initialize(retrieval, intent_id)
          @intent_id = intent_id
          @rulings = Knowledge::RulingOrder.sorted(retrieval.rulings(intent_id))
          @constraints = Knowledge::Spec.new(retrieval, intent_id).constraints
        end

        # The newest LIMIT rulings, oldest first, each with its id and text.
        def rulings = kept.map(&:id).zip(kept.map(&:text)).map { |id, text| { "id" => id, "text" => text } }

        # The first LIMIT constraints of the spec.
        def constraints = @constraints.first(LIMIT)

        # How many rulings and constraints the lists leave out; a list that left nothing out is absent.
        def omitted = { "rulings" => @rulings.size - LIMIT, "constraints" => @constraints.size - LIMIT }.select { |_kind, count| count.positive? }

        # The lines of the text answer: each ruling, each constraint, then what was left out.
        def lines
          [*rulings.map { |ruling| "ruling: #{ruling.fetch("id")} #{ruling.fetch("text")}" },
            *constraints.map { |text| "constraint: #{text}" },
            *omitted.map { |kind, count| "omitted: #{count} #{kind}; plastic intent brief #{@intent_id} lists them all" }]
        end

        private

        def kept = @rulings.last(LIMIT)
      end
    end
  end
end
