# frozen_string_literal: true

require_relative "../../lib/plastic/code_workflow"
require_relative "../../lib/plastic/routine"

# A command whose page has every word a page needs, for the test that a complete page is named nowhere.
module Fixtures
  module Worded
    module Workflows
      REGISTRY = { code_first_said: "FirstSaid", code_second_said: "SecondSaid" }.freeze

      class FirstSaid < Plastic::CodeWorkflow
        summary "Opens the thing."

        gate "%{problem}", stops: :failure, stops_when: "the thing is missing", pass: ->(_c) { true }
        step "open the thing", done: ->(_c) { true }, changes: { work: "The thing is opened" } do |_c|
        end

        outcome :done, because: "the thing was opened"
      end

      class SecondSaid < Plastic::CodeWorkflow
        summary "Closes the thing."

        outcome :done, because: "the thing was closed"
      end
    end

    class Routine < Plastic::Routine
      def self.workflows = Workflows
    end

    class Complete < Routine
      writes :work

      workflow :code_first_said, next: :code_second_said
      workflow :code_second_said, next: :noop
    end

    TABLE = { "worded complete" => ["Fixtures::Worded::Complete", "Run two workflows that say everything"] }.freeze
  end
end
