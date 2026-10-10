# frozen_string_literal: true

require_relative "../diagram"

module ArchitectureFigures
  module Delivery
    # The phases of delivery as a flow. See docs/contributing/ARCHITECTURE.md.
    module Phases
      META = Diagram::Meta.new(file: "delivery-phases.svg", width: 1160, height: 560, title: "How an intent is delivered",
        desc: "An intent starts in What, where it gets its context. Why grills it into a spec and rulings. The owner gives the go-ahead. How plans the work graph, runs the nodes, judges the result and opens the pull request. intent end or intent abandon closes it.")
      BOXES = Diagram.parse(<<~TABLE).freeze
        what | zone | 10 10 260 398 | WHAT | | | |
        why | zone | 290 10 260 398 | WHY | | | |
        go | zone | 570 10 240 398 | GO-AHEAD | | | |
        how | zone | 830 10 320 398 | HOW | | | |
        new | | 30 44 220 | intent new | 1  Start | code | mono | Writes the intent.
        discover | | 30 134 220 | intent discover | 2  Context | code | mono | Gathers what is known.
        spec | | 310 44 220 | intent spec | 3  Grilling | agent | mono | Asks until all is settled.
        rule | | 310 134 220 | intent rule | 4  One spec | agent | mono | Records each ruling.
        approve | | 590 94 200 | intent approve | 5  You say deliver | owner | mono | The go-ahead.
        add | | 850 44 280 | node add | 6  Plan the graph | code | mono | Nodes, and edges for the order.
        claim | | 850 134 280 | node claim | 7  Work the nodes | code | mono | Each node, claimed and done.
        judge | | 850 224 280 | intent judge | 8  Judge | agent | mono | Reasons over the finished work.
        pull | | 850 314 280 | Pull request | 9  Review | owner | | The owner approves and merges.
        finish | | 850 450 280 | intent end | 10  Close | end | mono | Records the completion.
        abandon | | 30 450 280 | intent abandon | Any time | line | mono | Closes an intent that stops.
      TABLE
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
