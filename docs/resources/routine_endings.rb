# frozen_string_literal: true

# Draws routine-endings.svg for docs/contributing/ARCHITECTURE.md: a chain of
# three workflows and the four values that end one routine call. Run it from
# the repository root:
#
#   ruby docs/resources/routine_endings.rb
module RoutineEndings
  COLORS = { ink: "#1f2328", line: "#57606a", ok: "#1a7f37", agent: "#0969da", failed: "#cf222e", owner: "#9a6700" }.freeze

  # One box: its top-left corner, its lines of text, and its outline color.
  Card = Data.define(:x, :y, :lines, :color)

  CARDS = [
    Card.new(20, 30, ["Code workflow", "gates, reads and steps", "in order"], :line),
    Card.new(270, 30, ["Code workflow", "its outcome picks", "the next edge"], :line),
    Card.new(520, 30, ["Agent workflow", "steps in plain words", "for the agent"], :line),
    Card.new(770, 30, ["End of chain", "the edge reaches", ":noop"], :line),
    Card.new(20, 220, ["Refused, exit 3", "a gate stops the call", "as a refusal"], :owner),
    Card.new(270, 220, ["Failed, exit 1", "a step breaks, or a gate", "stops the call as a failure"], :failed),
    Card.new(520, 220, ["HandedOff, exit 0", "steps are left; exit 1", "with stops: :failure"], :agent),
    Card.new(770, 220, ["Finished, exit 0", "prints next: and", "because:"], :ok)
  ].freeze

  # Each arrow as its two ends: along the chain, then down to each ending.
  ARROWS = [
    "220,75 268,75", "470,75 518,75", "720,75 768,75",
    "120,120 120,218", "370,120 370,218", "620,120 620,218", "870,120 870,218"
  ].freeze

  def self.call(path = File.join(__dir__, "routine-endings.svg")) = File.write(path, svg)

  def self.svg = [header, *CARDS.map { |card| card(card) }, *ARROWS.map { |ends| arrow(ends) }, tail].join("\n")

  def self.card(card)
    left, top = card.deconstruct.first(2)
    words = card.lines.each_with_index.map { |line, index| text(left + 100, top + 30 + (index * 22), line) }
    %(<rect x="#{left}" y="#{top}" width="200" height="90" rx="6" fill="none" stroke="#{COLORS.fetch(card.color)}" stroke-width="2"/>\n#{words.join("\n")})
  end

  def self.arrow(ends)
    %(<polyline points="#{ends}" fill="none" stroke="#{COLORS[:line]}" stroke-width="1.5" marker-end="url(#head)"/>)
  end

  def self.text(left, top, words)
    %(<text x="#{left}" y="#{top}">#{words}</text>)
  end

  def self.header
    <<~SVG.chomp
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 990 390" role="img" aria-label="A routine walks a chain of workflows and ends in one of four values">
      <style>text { font: 14px sans-serif; fill: #{COLORS[:ink]}; text-anchor: middle; } rect + text { font-weight: 700; }</style>
      <defs><marker id="head" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" fill="#{COLORS[:line]}"/></marker></defs>
      <rect width="990" height="390" fill="#ffffff"/>
    SVG
  end

  def self.tail
    <<~SVG
      <rect x="20" y="340" width="950" height="36" rx="6" fill="none" stroke="#{COLORS[:line]}" stroke-dasharray="5 4"/>
      <text x="495" y="363" style="font-weight: 400">A tool that writes saves its routine run row in work_graph.db after each workflow. The ending closes the row.</text>
      </svg>
    SVG
  end
end

RoutineEndings.call if $PROGRAM_NAME == __FILE__
