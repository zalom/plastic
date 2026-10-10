# frozen_string_literal: true

require_relative "../diagram"

module ArchitectureFigures
  module Delivery
    # The phases of delivery as a flow. See docs/contributing/ARCHITECTURE.md.
    module Phases
      META = Diagram::Meta.new(file: "delivery-phases.svg", width: 1160, height: 560, title: "How an intent is delivered",
        desc: "An intent starts in What, where it gets its context. Why grills it into a spec and rulings. The owner gives the go-ahead. How plans the work graph, runs the nodes, judges the result and opens the pull request. intent end or intent abandon closes it.")
      BOXES = {
        what: { type: :zone, left: 10, top: 10, width: 260, height: 398, name: "WHAT" },
        why: { type: :zone, left: 290, top: 10, width: 260, height: 398, name: "WHY" },
        go: { type: :zone, left: 570, top: 10, width: 240, height: 398, name: "GO-AHEAD" },
        how: { type: :zone, left: 830, top: 10, width: 320, height: 398, name: "HOW" },
        new: { left: 30, top: 44, width: 220, name: "intent new", mono: true, kind: "1  Start", tone: :code, lines: ["Writes the intent."] },
        discover: { left: 30, top: 134, width: 220, name: "intent discover", mono: true, kind: "2  Context", tone: :code, lines: ["Gathers what is known."] },
        spec: { left: 310, top: 44, width: 220, name: "intent spec", mono: true, kind: "3  Grilling", tone: :agent, lines: ["Asks until all is settled."] },
        rule: { left: 310, top: 134, width: 220, name: "intent rule", mono: true, kind: "4  One spec", tone: :agent, lines: ["Records each ruling."] },
        approve: { left: 590, top: 94, width: 200, name: "intent approve", mono: true, kind: "5  You say deliver", tone: :owner, lines: ["The go-ahead."] },
        add: { left: 850, top: 44, width: 280, name: "node add", mono: true, kind: "6  Plan the graph", tone: :code, lines: ["Nodes, and edges for the order."] },
        claim: { left: 850, top: 134, width: 280, name: "node claim", mono: true, kind: "7  Work the nodes", tone: :code, lines: ["Each node, claimed and done."] },
        judge: { left: 850, top: 224, width: 280, name: "intent judge", mono: true, kind: "8  Judge", tone: :agent, lines: ["Reasons over the finished work."] },
        pull: { left: 850, top: 314, width: 280, name: "Pull request", kind: "9  Review", tone: :owner, lines: ["The owner approves and merges."] },
        finish: { left: 850, top: 450, width: 280, name: "intent end", mono: true, kind: "10  Close", tone: :end, lines: ["Records the completion."] },
        abandon: { left: 30, top: 450, width: 280, name: "intent abandon", mono: true, kind: "Any time", tone: :line, lines: ["Closes an intent that stops."] }
      }.freeze
      ARROWS = [
        %w[new.bottom discover.top], %w[discover.right spec.left], %w[spec.bottom rule.top], %w[rule.right approve.left],
        %w[approve.right add.left], %w[add.bottom claim.top], %w[claim.bottom judge.top], %w[judge.bottom pull.top], %w[pull.bottom finish.top]
      ].freeze
      COMMANDS = ["intent new", "intent discover", "intent spec", "intent rule", "intent approve", "node add", "node claim", "intent judge", "intent end", "intent abandon"].freeze

      def self.files = Diagram.new(META, BOXES, ARROWS).files

      def self.names = COMMANDS.map { |name| ["command", name, name] }
    end
  end
end
