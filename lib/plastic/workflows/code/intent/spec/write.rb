# frozen_string_literal: true

require_relative "../spec"
require_relative "../../../../code_workflow"
require_relative "../../../given_file"
require_relative "../../../../graph/knowledge/spec_sections"
require_relative "../../../../layout"

module Plastic
  module Workflows
    module Code
      module Intent
        class Spec < CodeWorkflow
          # Writes the file that --from names as the whole spec.md of an open intent, a new revision; refuses a closed
          # intent and a text without the sections of the layout. A call without --from writes nothing.
          class Write < CodeWorkflow
            clear_declarations
            summary "Writes the file that --from names as the spec.md of the intent."

            CLOSED = %w[done abandoned].freeze
            FILE = Layout.name(:spec)

            sets :intent, :status, :spec_text, :spec_problem, :spec_reference

            read "find the intent" do |context|
              context[:intent] = context.retrieval.intent(context.intent_id)
              context[:status] = context.intent&.status
            end

            gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

            gate "intent %{intent_id} is %{status}; a closed intent keeps its spec", stops: :refusal,
              offers: "plastic next", because: "a closed intent keeps its spec; a new intent amends it",
              pass: ->(context) { context.from.nil? || !CLOSED.include?(context.status) }

            read "read the spec file" do |context|
              context[:spec_text], context[:spec_problem] = Write.text_of(context.from) if context.from
            end

            gate "%{spec_problem}", stops: :failure,
              words: "the spec file cannot be read or lacks a section of the layout",
              pass: ->(context) { context.spec_problem.nil? }

            step "write the spec", done: ->(context) { context.from.nil? || !context.spec_reference.nil? },
              changes: { knowledge: "spec.md holds the text of the file as its new revision", work: "A specified line in the work log" } do |context|
              context[:spec_reference] = context.work.write_document(context.intent_id, FILE, context.spec_text)
            end

            read "say what was written" do |context|
              context.print("spec: written from #{context.from}") if context.spec_reference
            end

            outcome :written, if: ->(context) { !context.spec_reference.nil? }, offers: nil, because: "spec.md holds the text of the file"
            outcome :kept, offers: nil, because: "no --from names a file, so spec.md stays as it is"

            # The text of the file and nil, or nil and why it cannot be the spec.
            def self.text_of(path)
              text, problem = GivenFile.text(path, "spec")
              [text, problem || Plastic::Graph::Knowledge::SpecSections.problem(text)]
            end
          end
        end
      end
    end
  end
end
