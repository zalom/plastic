# frozen_string_literal: true

require_relative "../../clock"
require_relative "../knowledge/outcome"

module Plastic
  module Graph
    module Work
      # The work rows of a project digest: the intents in play, the count of open
      # intents that wait, and the last deliveries with the day each closed and the line of its outcome that says how it landed.
      class IntentRows
        DELIVERED = 3

        def initialize(intents, slug, retrieval)
          @slug = slug
          @retrieval = retrieval
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
            .map { |(stamp, label)| ["delivered:", [day(stamp), label, landing(label)].compact.join(" ")] }
        end

        def day(stamp) = Plastic.local_day(stamp) || stamp.to_s[0, 10]

        # " - Merged: ..." or " - Committed: ..." from the intent's outcome.md, else nil. The label starts with the intent id.
        def landing(label)
          outcome = Knowledge::Outcome.new(@retrieval, label.split.first)
          line = %w[Merged Committed].lazy.filter_map { |name| outcome.values(name).first&.then { |value| "#{name}: #{value}" } }.first
          "- #{line}" if line
        end
      end
    end
  end
end
