# frozen_string_literal: true

module CommandReference
  module Figures
    # The drawing of a command that runs no chain: one box for its call.
    class Call
      def initialize(page)
        @page = page
      end

      def canvas
        drawing = Canvas.new(360, "The call of plastic #{@page.words}")
        drawing.rect(16, 16, 328, 56, "card")
        drawing.text(28, 36, label, "tag tag-muted")
        drawing.text(28, 56, @page.klass.name.split("::").last, "tb")
        drawing.text(332, 56, @page.words, "tm", anchor: "end")
        drawing
      end

      private

      def label = (@page.kind == :hook) ? "HOOK, ALWAYS EXIT 0" : "ONE CALL, NO CHAIN"
    end
  end
end
