# frozen_string_literal: true

require "cgi"

module CommandReference
  module Figures
    # The SVG around the shapes of a drawing.
    Frame = Data.define(:width, :height, :title, :parts) do
      def markup(style)
        [opening, "<title>#{CGI.escapeHTML(title)}</title>", style, %(<rect width="100%" height="100%" class="ground"/>), *parts, "</svg>"].join("\n")
      end

      private

      def opening = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width} #{height}" width="#{width}" height="#{height}" role="img" xml:space="preserve">)
    end
  end
end
