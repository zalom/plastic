# frozen_string_literal: true

module CommandReference
  module Dsl
    # Shared by the sections of the DSL page: a heading, a drawing, and links into the kernel.
    class Section
      def initialize(dsl, links)
        @dsl = dsl
        @links = links
      end

      private

      def link(key, pattern) = @links.code(DslPage::FILES.fetch(key), @dsl.line(key, pattern))

      def opening(title, image, alt) = ["---", "", "## #{title}", "", "![#{alt}](#{image})", ""]
    end

    # Declare a command.
    class CommandSection < Section
      def lines
        [*opening("Declare a command", "declare-command.svg", "The plastic #{@dsl.page.words} class beside what each part of it declares"),
          "The class of [`plastic #{@dsl.page.words}`](../commands/#{@dsl.page.slug}/README.md), from #{@links.code(@dsl.page.file, @dsl.page.line)}. " \
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

    # Wire the chain.
    class ChainSection < Section
      def lines
        [*opening("Wire the chain", "chain.svg", "The chain of plastic #{@dsl.page.words}"),
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

    # Declare a code workflow.
    class CodeSection < Section
      def lines
        flow = @dsl.code_flow
        [*opening("Declare a code workflow", "code-workflow.svg", "The #{Words.short(flow)} workflow beside what each line does when it runs"),
          "`#{Words.short(flow)}`, the workflow `:#{flow.key}`, from #{@links.code(@dsl.flow_file(flow), @dsl.flow_line(flow))}. " \
          "The lines run from top to bottom. A block shows as `do ... end`, code that is not a DSL line shows as a gap, and long lines are wrapped and cut short.", "",
          "| Word | Shape | When it runs | Stops the call | Defined in |", "| --- | --- | --- | --- | --- |", *rows, "",
          "A block does the work. A keyword lambda, `done:`, `pass:` or `if:`, answers a question and changes nothing.", "",
          "An outcome that ends the chain also takes `offers:`, the command that `next:` prints, and `because:`, the reason for it.", ""]
      end

      private

      def rows
        [
          "| `sets` | `sets :intent, :status` | when the class loads | never | #{link(:workflow, /def sets\b/)} |",
          "| `read` | `read \"name\" do` then `end` | on every call, a rerun included | only when it raises: exit 1 | #{link(:code, /def read\b/)} |",
          "| `gate` | `gate \"reason\", stops: :failure, pass: ->(c) { ... }` | in its place | when `pass:` is false: exit 1, the agent can fix it | #{link(:code, /def gate\b/)} |",
          "| `gate` | `gate \"reason\", stops: :refusal, pass: ->(c) { ... }` | in its place | when `pass:` is false: exit 3, the owner's step | #{link(:code, /def gate\b/)} |",
          "| `step` | `step \"name\", done: ->(c) { ... } do` then `end` | while `done:` is false, and `done:` must hold after it | when it raises: exit 1 | #{link(:code, /def step\b/)} |",
          "| `forget_stop` | `forget_stop :problem` | on every call | never | #{link(:code, /def forget_stop\b/)} |",
          "| `outcome` | `outcome :name, if: ->(c) { ... }` | after the steps: the first whose `if:` holds wins | never | #{link(:code, /def outcome\b/)} |",
          "| `outcome` | `outcome :name` | the fallback, with no `if:`; it comes last | never | #{link(:code, /the last outcome line needs no if/)} |"
        ]
      end
    end

    # Declare an agent workflow.
    class AgentSection < Section
      def lines
        flow = @dsl.agent_flow
        [*opening("Declare an agent workflow", "agent-workflow.svg", "The #{Words.short(flow)} workflow beside what a call prints for the agent"),
          "`#{Words.short(flow)}`, the workflow `:#{flow.key}`, from #{@links.code(@dsl.flow_file(flow), @dsl.flow_line(flow))}.", "",
          "| Word | Shape | What it does | Defined in |", "| --- | --- | --- | --- |", *rows, "",
          "An agent workflow always ends the chain. The agent reports its work through a plastic command, and the next call checks the steps again.", ""]
      end

      private

      def rows
        [
          "| `step` | `step \"name\", done: ->(c) { ... }, say: \"... %{fact} ...\"` | One thing the agent does. A call prints the `say:` text of each step whose `done:` check fails, with every `%{fact}` filled in. | #{link(:agent, /def step\b/)} |",
          "| `outcome :handoff` | `outcome :handoff, offers:, because:` | Ends the call while a step is left: exit 0, or exit 1 with `stops: :failure`. | #{link(:agent, /def handoff_exit_code\b/)} |",
          "| `outcome :done` | `outcome :done, offers:, because:` | Ends the call once every `done:` check holds. | #{link(:agent, /def call\b/)} |"
        ]
      end
    end
  end
end
