# frozen_string_literal: true

module CommandReference
  module Dsl
    # Declare a command.
    class CommandSection < Section
      def lines
        page = dsl.page
        words = page.words
        [*opening("Declare a command", "declare-command.svg", "The plastic #{words} class beside what each part of it declares"),
          "The class of [`plastic #{words}`](../commands/#{page.slug}/README.md), from #{links.code(page.file, page.line)}. " \
          "The numbers match each part of the class to what it declares. Long lines are wrapped.", "",
          "| # | Word | What it declares | Defined in |", "| --- | --- | --- | --- |", *rows, ""]
      end

      private

      def rows
        [
          "| 1 | `class Name < Routine` | The class is the command, and it runs a chain of workflows. | #{link(:routine, /^\s*class Routine\b/)} |",
          "| 2 | `intent_subject` | The intent id as the first argument, and the subject of the call. | #{link(:declarations, /def intent_subject\b/)} |",
          "| 2 | `node_subject` | An intent id and a node id, as the first two arguments. | #{link(:declarations, /def node_subject\b/)} |",
          "| 2 | `argument :name, label:, text:` | One word the command takes. `rest: true` takes every word left, and `optional: true` allows none. | #{link(:declarations, /def argument\b/)} |",
          "| 2 | `option :name, switch:, text:` | One switch. `default:` gives its value when the call leaves it out. | #{link(:declarations, /def option\b/)} |",
          "| 3 | `reads :graph`, `writes :graph` | The graphs the command reads and writes: #{Plastic::CLI::Declarations::GRAPHS.join(", ")}. | #{link(:declarations, /def reads\b/)} |",
          "| 4 | `def call` then `super` | A check of its own before the chain. A usage error prints the usage line and exits 2. | #{link(:command, /USAGE = 2/)} |",
          "| 5 | `workflow` | One link of the chain, explained in [Wire the chain](#wire-the-chain). | #{link(:routine, /def workflow\b/)} |"
        ]
      end
    end
  end
end
