# frozen_string_literal: true

module CommandReference
  module Figures
    # One workflow's run: its steps from the top down, where it stops on the right, its outcomes at the bottom.
    class Workflow
      WIDTH = 760
      SPINE = 16

      def initialize(page, flow)
        @page = page
        @flow = flow
        @drawing = Canvas.new(WIDTH, "How #{flow.short} runs in plastic #{page.words}")
      end

      def canvas = @canvas ||= paint

      private

      def paint
        heading
        bottom = @flow.rows.reduce(34) { |top, row| StepBox.new(@drawing, row).draw(top) + 10 }
        Outcomes.new(@drawing, @page, @flow).draw(bottom + 4)
        @drawing
      end

      def heading
        @drawing.text(Point.new(SPINE, 22), @flow.short, "tb")
        @drawing.text(Point.new(SPINE + StepBox::WIDE, 22).ending, @flow.location, "tm tag-muted")
      end
    end
  end
end
