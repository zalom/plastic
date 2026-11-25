# frozen_string_literal: true

require "cgi/escape"

module ArchitectureFigures
  module Shapes
    def self.text(at, style, content)
      left, top, anchor = at
      tail = anchor ? %( text-anchor="#{anchor}") : ""
      %(<text class="#{style}" x="#{left}" y="#{top}"#{tail}>#{CGI.escapeHTML(content)}</text>)
    end
  end
end
