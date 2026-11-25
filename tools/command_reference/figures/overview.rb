# frozen_string_literal: true

module CommandReference
  module Figures
    # How one call moves from workflow to workflow, in words: a card for each workflow and for each way the call ends.
    class Overview
      def initialize(page)
        @page = page
        @tree = Tree.new(page)
      end

      def canvas
        words = @page.words
        Canvas.new(@tree.width, "The workflows of one call of plastic #{words}, in words").tap do |found|
          found.text(Point.new(Tree::MARGIN, 34), "One call of plastic #{words}: its workflows and its endings", "tb")
          Placement.new(@tree, Reasons.new(@page), found).paint
        end
      end
    end
  end
end
