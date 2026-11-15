# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Intent
        # Writes a new intent's rows; the command prints its folder and store/index.json.
        class New < CodeWorkflow
          # Declares the whole chain, so a second load of the class replaces the first.
          clear_declarations

          sets :problem, :intent_id, :linked

          read "check the call" do |context|
            context[:problem] = context.work.intent_problem(parent_id: context.parent_id, ref: context.ref, status: context.status,
              reason: context.reason) ||
              after_problem(context)
          end

          gate "%{problem}", stops: :failure,
            stops_when: "the parent, the reference, the status or the source of the new intent is not valid",
            pass: ->(context) { context.problem.nil? }

          step "write the intent", done: ->(context) { !context.intent_id.nil? },
            changes: { work: "The intent is written with its first savepoint", knowledge: "The spec document of the intent is created" } do |context|
            intent = context.work.write_intent(title: context.title, parent_id: context.parent_id, ref: context.ref, kind: context.kind,
              status: context.status, reason: context.reason)
            context[:intent_id] = intent.intent_id
          end

          step "link to what it grows out of", done: ->(context) { context.after.nil? || !context.linked.nil? },
            changes: { knowledge: "A source link from the new intent to the intent it grows out of is added" } do |context|
            context.work.add_link(from_ref: context.intent_id, to_ref: context.after, kind: "source")
            context[:linked] = true
          end

          read "say what was written" do |context|
            context.print("intent: #{context.intent_id}")
            context.print(store_line(context.retrieval.store))
            context.print(context.work.ref_line(context.ref)) if context.ref
          end

          outcome :done, offers: "plastic next", because: "intent %{intent_id} has its rows and its files"

          def self.store_line(store) = (store == "global") ? "store: global, because no project names this folder" : "store: #{store}"

          def self.after_problem(context)
            after = context.after
            return unless after

            "no intent #{after} in this store to link after" unless context.retrieval.intent(after)
          end
        end
      end
    end
  end
end
