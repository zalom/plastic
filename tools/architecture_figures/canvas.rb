# frozen_string_literal: true

require "cgi/escape"
require_relative "shapes/palette"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  class Canvas
    FONT = "IBM Plex Sans, system-ui, -apple-system, Segoe UI, sans-serif"

    def initialize(file, width, height, title, desc)
      @id = File.basename(file, ".svg")
      @size = [width, height]
      @words = [title, desc]
      @parts = []
    end

    def add(shape) = @parts << shape.markup(@id)

    def to_svg
      <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{@size.join(" ")}" role="img" aria-labelledby="#{@id}-title #{@id}-desc" font-family="#{FONT}">
          <title id="#{@id}-title">#{CGI.escapeHTML(@words.first)}</title>
          <desc id="#{@id}-desc">#{CGI.escapeHTML(@words.last)}</desc>
          <defs><marker id="#{@id}-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#{Palette.color(:line)}"/></marker></defs>
          <style>#{Palette.css}</style>
          <rect class="background" width="100%" height="100%"/>
        #{@parts.join("\n")}
        </svg>
      SVG
    end
  end
end
