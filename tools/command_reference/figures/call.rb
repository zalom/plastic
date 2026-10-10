# frozen_string_literal: true

module CommandReference
  module Figures
    # The drawing of a command that runs no chain: one box for its call.
    class Call
      def initialize(page)
        @page = page
        @drawing = Canvas.new(360, "The call of plastic #{page.words}")
      end

      def canvas = @canvas ||= paint

      private

      def paint
        frame = Box.new(16, 16, 328, 56)
        @drawing.rect(frame, "card")
        caption(frame)
        @drawing
      end

      def caption(frame)
        @drawing.text(frame.at(12, 20), label, "tag tag-muted")
        @drawing.text(frame.at(12, 40), Words.short(@page.klass), "tb")
        @drawing.text(frame.at(316, 40).ending, @page.words, "tm")
      end

      def label = (@page.kind == :hook) ? "HOOK, ALWAYS EXIT 0" : "ONE CALL, NO CHAIN"
    end
  end
end
