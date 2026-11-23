# frozen_string_literal: true

require_relative "../../clock"
require_relative "delivered_intent"

module Plastic
  module Graph
    module Work
      # The work rows of a project digest: the intents in play, the count of open
      # intents that wait, and the last deliveries with the day each closed and the line of its outcome that says how it landed.
      class IntentRows
        DELIVERED = 3

        def initialize(intents, slug, retrieval)
          @slug = slug
          by_status = intents.group_by(&:status)
          @started = by_status.fetch("in_progress", []).map(&:label)
          @open = by_status.fetch("open", []).size
          @closed = by_status.fetch("done", []).select(&:closed_at).map { |intent| DeliveredIntent.new(intent.closed_at, intent.label, retrieval) }
        end

        def rows = [*in_play, waiting, *delivered]

        private

        def in_play = (@started.empty? ? ["none"] : @started).map { |label| ["in play:", label] }

        def waiting = ["waiting:", "#{@open} open #{(@open == 1) ? "intent" : "intents"}; plastic status --project #{@slug} lists them"]

        def delivered = @closed.max_by(DELIVERED) { |delivery| Plastic.utc(delivery.stamp).to_s }.map { |delivery| ["delivered:", delivery.to_s] }
      end
    end
  end
end
