# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "archive_before"

module Plastic
  module Workflows
    module Code
      module Intent
        # Takes a done, abandoned or future intent off the checkout, or each one older than a date. Its rows stay.
        class Archive < CodeWorkflow
          clear_declarations

          def self.archive_one(context)
            ok, problem, kind = context.work.archive_intent(context.intent_id)
            context[:ok] = ok
            context[:problem] = problem
            context[:kind] = kind
            context[:lines] = ["intent: #{context.intent_id} archived"]
          end

          sets :problem, :kind, :ok, :lines

          forget_stop :problem, :kind, :ok, :lines

          step "archive the intent", done: ->(context) { !context.ok.nil? || !context.problem.nil? },
            changes: { work: "The intent is marked archived", references: "The files of the intent are kept in the references database" } do |context|
            if context.older_than
              context[:lines] = ArchiveBefore.new(context).lines
              context[:ok] = true
            else
              archive_one(context)
            end
          end

          gate "%{problem}", stops: :failure, offers: "plastic intent end %{intent_id}",
            because: "only a done, abandoned or future intent archives; end it first",
            pass: ->(context) { context.kind != :unfinished }
          gate "%{problem}", stops: :failure,
            stops_when: "the intent is not in the store, or a file of the store cannot be read or written",
            pass: ->(context) { context.kind != :failure }
          gate "%{problem}", stops: :refusal,
            stops_when: "an intent that is still open links to the intent",
            pass: ->(context) { context.kind != :refusal }

          read "say what was archived" do |context|
            context.lines.each { |line| context.print(line) }
          end

          outcome :done, offers: "plastic status", because: "the intents named above are off the checkout"
        end
      end
    end
  end
end
