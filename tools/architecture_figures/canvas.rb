# frozen_string_literal: true

require "cgi/escape"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Palette
    LIGHT = {
      ink: "#1f2530", muted: "#3f4754", line: "#6b7483", paper: "#e9e5dc", card: "#f4f1ea", rule: "#c9c3b6",
      code: "#0b5e55", agent: "#7d4405", owner: "#4a2a99", owner_bg: "#e4dcf5", end: "#23406f", end_bg: "#d9e2f0"
    }.freeze
    DARK = {
      ink: "#e8e6e1", muted: "#b4bac4", line: "#8a93a3", paper: "#1d2128", card: "#262b34", rule: "#3b424e",
      code: "#5fd0c0", agent: "#e0a24f", owner: "#b9a2ff", owner_bg: "#2f2750", end: "#8fb0e8", end_bg: "#1f2d45"
    }.freeze

    MONO = 'font-family: "IBM Plex Mono", ui-monospace, Menlo, monospace;'
    RULES = {
      background: "fill: {paper};", box: "fill: {card}; stroke: {line}; stroke-width: 1;",
      zone: "fill: none; stroke: {line}; stroke-width: 1.2; stroke-dasharray: 6 4;",
      t: "fill: {ink}; font-size: 14px; font-weight: 600;", s: "fill: {muted}; font-size: 11.5px;",
      al: "fill: {ink}; font-size: 11.5px; stroke: {paper}; stroke-width: 4px; paint-order: stroke;",
      m: "fill: {ink}; #{MONO} font-size: 12px; font-weight: 600;", r: "fill: {ink}; #{MONO} font-size: 11px;",
      flow: "stroke: {line}; stroke-width: 1.5; fill: none;"
    }.freeze

    def self.color(name) = "var(--#{name.to_s.tr("_", "-")}, #{LIGHT.fetch(name)})"

    def self.tokens(colors) = colors.map { |name, hex| "--#{name.to_s.tr("_", "-")}: #{hex};" }.join(" ")

    def self.css
      rules = RULES.map { |name, body| ".#{name} { #{body.gsub(/\{(\w+)\}/) { color(Regexp.last_match(1).to_sym) }} }" }
      ["svg { #{tokens(LIGHT)} }", "@media (prefers-color-scheme: dark) { svg { #{tokens(DARK)} } }", *rules].join("\n")
    end
  end

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
