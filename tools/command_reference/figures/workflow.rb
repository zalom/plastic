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
      end

      def canvas
        drawing = Canvas.new(WIDTH, "How #{Words.short(@flow.klass)} runs in plastic #{@page.words}")
        drawing.text(SPINE, 22, Words.short(@flow.klass), "tb")
        drawing.text(SPINE + 420, 22, "#{File.basename(@flow.file)}:#{@flow.line}", "tm tag-muted", anchor: "end")
        bottom = @flow.rows.reduce(34) { |top, row| StepBox.new(drawing, @flow, row).draw(top) + 10 }
        Outcomes.new(drawing, @page, @flow).draw(bottom + 4)
        drawing
      end
    end
  end
end
