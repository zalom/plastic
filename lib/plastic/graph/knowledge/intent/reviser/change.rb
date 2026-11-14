# frozen_string_literal: true

require_relative "../revision"

module Plastic
  module Graph
    module Knowledge
      class Intent
        class Reviser
          # One revise of one intent: the file row it starts from, the qualified
          # reference of that row's revision, and the new What and Why.
          Change = Data.define(:intent, :document, :history, :line, :why) do
            def revision = Revision.new(document.body, intent.intent_id)

            def old_why = revision.why.sub(/\A\z/, "none")

            def body = revision.revise(line, why)

            # Why the change cannot be written, or nil.
            def problem = line_problem || same_problem

            private

            def line_problem
              "the new What is one line; it holds a line break" if line.include?("\n")
            end

            def same_problem
              "intent #{intent.intent_id} already reads this What and Why; nothing to change" if line == intent.title && body == document.body
            end
          end
        end
      end
    end
  end
end
