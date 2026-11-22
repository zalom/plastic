# frozen_string_literal: true

require_relative "../../clock"

module Plastic
  module Graph
    module Work
      # The work rows of a project digest: the intents in play, the count of open
      # intents that wait, and the last deliveries with the day each closed.
      class IntentRows
        DELIVERED = 3

        def initialize(intents, slug)
          @slug = slug
          by_status = intents.group_by(&:status)
          @started = by_status.fetch("in_progress", []).map(&:label)
          @open = by_status.fetch("open", []).size
          @closed = by_status.fetch("done", []).map { |intent| [intent.closed_at, intent.label] }.select(&:first)
        end

        def rows = [*in_play, waiting, *delivered]

        private

        def in_play = (@started.empty? ? ["none"] : @started).map { |label| ["in play:", label] }

        def waiting = ["waiting:", "#{@open} open #{(@open == 1) ? "intent" : "intents"}; plastic status --project #{@slug} lists them"]

        # The day a stored time falls on here; an older date-only value shows as it is.
        def delivered
          @closed.max_by(DELIVERED) { |(stamp, _)| Plastic.utc(stamp).to_s }
            .map { |(stamp, label)| ["delivered:", "#{Plastic.local_day(stamp) || stamp.to_s[0, 10]} #{label}"] }
        end
      end
    end
  end
end
