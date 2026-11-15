# frozen_string_literal: true

require_relative "../../lib/plastic/code_workflow"
require_relative "../../lib/plastic/routine"

# Commands whose pages lack the words a page needs, for the tests of the check that the words are complete.
module Fixtures
  module Wordless
    module Workflows
      REGISTRY = { code_unsaid: "Unsaid", code_askless: "Askless", code_forked: "Forked" }.freeze

      class Unsaid < Plastic::CodeWorkflow
        outcome :done, because: "nothing was said"
      end

      class Askless < Plastic::CodeWorkflow
        gate "%{problem}", stops: :failure, pass: ->(_c) { true }

        outcome :done, because: "nothing was asked"
      end

      class Forked < Plastic::CodeWorkflow
        outcome :left, if: ->(_c) { false }
        outcome :right, because: "the right branch was taken"
      end
    end

    class Routine < Plastic::Routine
      def self.workflows = Workflows
    end

    class Chained < Routine
      workflow :code_unsaid, next: :code_askless
      workflow :code_askless, next: :noop
    end

    class Branching < Routine
      workflow :code_forked, next: :code_unsaid
      workflow :code_unsaid, next: :noop
    end

    class Lone < Routine
      writes :work

      workflow :code_unsaid, next: :noop
    end

    class Bare < Plastic::CLI::Command
      writes :work
    end

    TABLE = {
      "wordless chained" => ["Fixtures::Wordless::Chained", "Run two workflows that say nothing"],
      "wordless branching" => ["Fixtures::Wordless::Branching", "Branch with no words"],
      "wordless lone" => ["Fixtures::Wordless::Lone", "Write the work graph with no words"],
      "wordless bare" => ["Fixtures::Wordless::Bare", "Run a command with no workflow and no words"]
    }.freeze
  end
end
