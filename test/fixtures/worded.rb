# frozen_string_literal: true

require_relative "../../lib/plastic/code_workflow"
require_relative "../../lib/plastic/agent_workflow"
require_relative "../../lib/plastic/routine"

# A command whose page has every word a page needs, for the test that a complete page is named nowhere.
module Fixtures
  module Worded
    module Workflows
      REGISTRY = { code_first_said: "FirstSaid", code_second_said: "SecondSaid", agent_relay_said: "RelaySaid" }.freeze

      class FirstSaid < Plastic::CodeWorkflow
        summary "Opens the thing."

        gate "%{problem}", stops: :failure, words: "the thing is missing", pass: ->(_c) { true }
        step "open the thing", done: ->(_c) { true }, changes: { work: "The thing is opened" } do |_c|
        end

        outcome :done, because: "the thing was opened"
      end

      class SecondSaid < Plastic::CodeWorkflow
        summary "Closes the thing."

        outcome :done, because: "the thing was closed"
      end

      class RelaySaid < Plastic::AgentWorkflow
        summary "Relays a text."

        step "relay the text", done: ->(_c) { true }, say: "%{text}", words: "The text of the next step of the delivery"
        outcome :handoff, offers: nil, because: "%{why}", words: "the next step is handed to the agent"
        outcome :done, offers: nil, because: "the text was relayed"
      end
    end

    class Routine < Plastic::Routine
      def self.workflows = Workflows
    end

    class Complete < Routine
      writes :work

      workflow :code_first_said, next: :code_second_said
      workflow :code_second_said, next: :agent_relay_said
      workflow :agent_relay_said, next: :noop
    end

    TABLE = { "worded complete" => ["Fixtures::Worded::Complete", "Run two workflows that say everything"] }.freeze
  end
end
