# frozen_string_literal: true

module CommandReference
  module Figures
    # The events of one call, step by step, in words: numbered boxes with the stops beside them.
    class Events
      WIDTH = 834

      def initialize(page)
        @page = page
      end

      def canvas = blank.tap { |found| paint(found) }

      private

      def blank
        words = @page.words
        Canvas.new(WIDTH, "The events of one call of plastic #{words}, in words").tap do |found|
          found.text(Point.new(24, 34), "One call of plastic #{words}, from top to bottom", "tb")
        end
      end

      def paint(found)
        ([nil] + rows).each_cons(2) { |previous, row| row.draw(found, previous) }
        legend(found, rows.last.bottom + 30)
      end

      def legend(found, top)
        key.draw(found, top)
        found.grow(top + key.height)
      end

      def key = EventKey.new(events)

      def events = @events ||= EventList.new(@page).events

      def rows
        @rows ||= events.each_with_object([]) { |event, all| all << EventRow.after(all, event) }
      end
    end
  end
end
