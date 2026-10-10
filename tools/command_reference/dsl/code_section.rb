# frozen_string_literal: true

module CommandReference
  module Dsl
    # Declare a code workflow.
    class CodeSection < Section
      def lines
        flow = dsl.code_flow
        name = Words.short(flow)
        [*opening("Declare a code workflow", "code-workflow.svg", "The #{name} workflow beside what each line does when it runs"),
          "`#{name}`, the workflow `:#{flow.key}`, from #{links.code(dsl.flow_file(flow), dsl.flow_line(flow))}. " \
          "The lines run from top to bottom. A block shows as `do ... end`, code that is not a DSL line shows as a gap, and long lines are wrapped and cut short.", "",
          "| Word | Shape | When it runs | Stops the call | Defined in |", "| --- | --- | --- | --- | --- |", *rows, "",
          "A block does the work. A keyword lambda, `done:`, `pass:` or `if:`, answers a question and changes nothing.", "",
          "An outcome that ends the chain also takes `offers:`, the command that `next:` prints, and `because:`, the reason for it.", ""]
      end

      private

      def rows = [*head_rows, *gate_rows, *tail_rows]

      def head_rows
        [
          "| `sets` | `sets :intent, :status` | when the class loads | never | #{link(:workflow, /def sets\b/)} |",
          "| `read` | `read \"name\" do` then `end` | on every call, a rerun included | only when it raises: exit 1 | #{link(:code, /def read\b/)} |"
        ]
      end

      def gate_rows
        gate = link(:code, /def gate\b/)
        [
          "| `gate` | `gate \"reason\", stops: :failure, pass: ->(c) { ... }` | in its place | when `pass:` is false: exit 1, the agent can fix it | #{gate} |",
          "| `gate` | `gate \"reason\", stops: :refusal, pass: ->(c) { ... }` | in its place | when `pass:` is false: exit 3, the owner's step | #{gate} |"
        ]
      end

      def tail_rows
        [
          "| `step` | `step \"name\", done: ->(c) { ... } do` then `end` | while `done:` is false, and `done:` must hold after it | when it raises: exit 1 | #{link(:code, /def step\b/)} |",
          "| `forget_stop` | `forget_stop :problem` | on every call | never | #{link(:code, /def forget_stop\b/)} |",
          "| `outcome` | `outcome :name, if: ->(c) { ... }` | after the steps: the first whose `if:` holds wins | never | #{link(:code, /def outcome\b/)} |",
          "| `outcome` | `outcome :name` | the fallback, with no `if:`; it comes last | never | #{link(:code, /the last outcome line needs no if/)} |"
        ]
      end
    end
  end
end
