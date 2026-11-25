# frozen_string_literal: true

module ArchitectureFigures
  module Delivery
    # The phases of delivery as a flow. See docs/contributing/ARCHITECTURE.md.
    module Phases
      META = Diagram::Meta.new(file: "delivery-phases.svg", width: 1160, height: 560, title: "How an intent is delivered",
        desc: "An intent is written future in What, started for guided work or agent delivery, and gets its context. Why grills it into a spec and rulings. The go-ahead follows: the owner gives it in guided work, the agents record it in auto. How plans the work graph, runs the nodes, judges the result and opens the pull request. intent park parks started work with its reason, and intent end or intent abandon closes the intent.")
      BOXES = Diagram.parse(<<~TABLE).freeze
        what | zone | 10 10 260 398 | WHAT | | | |
        why | zone | 290 10 260 398 | WHY | | | |
        go | zone | 570 10 240 398 | GO-AHEAD | | | |
        how | zone | 830 10 320 398 | HOW | | | |
        new | | 30 44 220 | intent new | 1  Write | code | mono | Writes a future intent.
        start | | 30 134 220 | intent start | 2  Start | code | mono | Or intent auto, for agents.
        discover | | 30 224 220 | intent discover | 3  Context | code | mono | Gathers what is known.
        spec | | 310 44 220 | intent spec | 4  Grilling | agent | mono | Asks until all is settled.
        rule | | 310 134 220 | intent rule | 5  One spec | agent | mono | Rulings, and revisions.
        approve | | 590 94 200 | intent approve | 6  You say deliver | owner | mono | The go-ahead; agents in auto.
        add | | 850 44 280 | node add | 7  Plan the graph | code | mono | Nodes, and edges for the order.
        claim | | 850 134 280 | node claim | 8  Work the nodes | code | mono | Each node, claimed and done.
        judge | | 850 224 280 | intent judge | 9  Judge | agent | mono | Reasons over the finished work.
        pull | | 850 314 280 | Pull request | 10  Review | owner | | The agent merges; the owner approves when review is on.
        finish | | 850 450 280 | intent end | 11  Close | end | mono | Records the completion.
        park | | 440 450 280 | intent park | While in progress | line | mono | Parks the work with its reason.
        abandon | | 30 450 280 | intent abandon | Any time | line | mono | Closes an intent that stops.
      TABLE
      ARROWS = [
        %w[new.bottom start.top], %w[start.bottom discover.top], %w[discover.right spec.left], %w[spec.bottom rule.top], %w[rule.right approve.left],
        %w[approve.right add.left], %w[add.bottom claim.top], %w[claim.bottom judge.top], %w[judge.bottom pull.top], %w[pull.bottom finish.top]
      ].freeze
      COMMANDS = ["intent new", "intent start", "intent auto", "intent discover", "intent spec", "intent rule", "intent approve", "node add", "node claim", "intent judge", "intent end", "intent park", "intent abandon"].freeze

      def self.diagrams = [Diagram.new(META, BOXES, ARROWS)]

      def self.files = Diagram.merge(diagrams)

      def self.names = COMMANDS.map { |name| ["command", name, name] }
    end
  end
end
