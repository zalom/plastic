# frozen_string_literal: true

module CommandReference
  module Figures
    # A small filled dot, such as the number on a note.
    Circle = Data.define(:center, :css) do
      def bottom = center.top + 8

      def markup = %(<circle cx="#{center.left}" cy="#{center.top}" r="8" class="#{css}"/>)
    end
  end
end
