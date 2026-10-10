# frozen_string_literal: true

require "cgi"

module CommandReference
  module Figures
    # One run of words at a place, anchored at its start, middle or end.
    Label = Data.define(:place, :words, :css) do
      def markup = %(<text x="#{place.left}" y="#{place.top}" class="#{css}" text-anchor="#{place.side}">#{CGI.escapeHTML(words.to_s)}</text>)
    end
  end
end
