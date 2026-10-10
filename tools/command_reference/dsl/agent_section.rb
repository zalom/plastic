# frozen_string_literal: true

module CommandReference
  module Dsl
    # Declare an agent workflow.
    class AgentSection < Section
      def lines
        flow = dsl.agent_flow
        name = Words.short(flow)
        [*opening("Declare an agent workflow", "agent-workflow.svg", "The #{name} workflow beside what a call prints for the agent"),
          "`#{name}`, the workflow `:#{flow.key}`, from #{links.code(dsl.flow_file(flow), dsl.flow_line(flow))}.", "",
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
