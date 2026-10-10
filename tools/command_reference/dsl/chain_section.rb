# frozen_string_literal: true

module CommandReference
  module Dsl
    # Wire the chain.
    class ChainSection < Section
      def lines
        [*opening("Wire the chain", "chain.svg", "The chain of plastic #{dsl.page.words}"),
          "Each `workflow` line draws a box, and each `on` line draws a wire between two boxes, labeled with the outcomes it carries.", "",
          "| Line | What it means | Defined in |", "| --- | --- | --- |", *rows, "",
          "The first `workflow` line is the entry. An `on` line wins over a plain `next:`.", "",
          "Before the first call, `verify` checks the wiring and raises every fault at once, from #{link(:routine, /def verify\b/)}. It refuses a chain when:", "",
          "| Fault | Checked in |", "| --- | --- |", *faults, ""]
      end

      private

      def rows
        [
          "| `workflow :key do` then `end` | Runs `:key`. The `on` lines inside say where each outcome goes. | #{link(:routine, /def workflow\b/)} |",
          "| `on :outcome, next: :key` | That outcome runs `:key` next. | #{link(:branches, /def on\b/)} |",
          "| `workflow :key, next: :other` | Every outcome of `:key` runs `:other` next. | #{link(:chain, /def add\b/)} |",
          "| `next: :noop` | The chain ends after `:key`. Its outcome line gives the `next:` and `because:` lines the call prints. | #{link(:workflow, /def closing\b/)} |"
        ]
      end

      def faults
        [
          ["An edge points to a key that is not in the chain.", :edge, /is a target but not in the chain/],
          ["An edge points backward, so the chain could loop.", :edge, /points backward/],
          ["The entry cannot reach a workflow.", :chain, /cannot be reached from/],
          ["An outcome has no edge.", :link, /has no edge for/],
          ["An edge names an outcome its workflow never returns.", :link, /which it never returns/],
          ["Anything but `:noop` follows an agent workflow.", :link, /must end the chain/],
          ["An outcome that ends the chain has no `because:` line.", :link, /no outcome line gives its because/],
          ["A workflow prints a `%{name}` that nothing declares.", :link, /which no one declares/]
        ].map { |fault, key, pattern| "| #{fault} | #{link(key, pattern)} |" }
      end
    end
  end
end
