# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Writes a new intent's rows, then prints its folder and store/index.json.
    class WriteIntent < CodeWorkflow
      # Declares the whole chain, so a second load of the class replaces the first.
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :intent_id, :linked, :printed_paths

      read "check the call" do |context|
        context[:problem] = context.work.intent_problem(parent_id: context.parent_id, ref: context.ref, status: context.status) ||
          after_problem(context)
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      step "write the intent", done: ->(context) { !context.intent_id.nil? } do |context|
        intent = context.work.write_intent(title: context.title, parent_id: context.parent_id, ref: context.ref, kind: context.kind,
          status: context.status)
        context[:intent_id] = intent.intent_id
      end

      step "link to what it grows out of", done: ->(context) { context.after.nil? || !context.linked.nil? } do |context|
        context.work.add_link(from_ref: context.intent_id, to_ref: context.after, kind: "source")
        context[:linked] = true
      end

      step "print its files", done: ->(context) { !context.printed_paths.nil? } do |context|
        context[:printed_paths] = context.work.print_intent(context.intent_id)
      end

      read "say what was written" do |context|
        context.print("intent: #{context.intent_id}")
        context.print(context.work.ref_line(context.ref)) if context.ref
        context.printed_paths.each { |path| context.print("printed #{path}") }
      end

      outcome :done, offers: "plastic next", because: "intent %{intent_id} has its rows and its printed files"

      def self.after_problem(context)
        "no intent #{context.after} in this store to link after" if context.after && !context.retrieval.intent(context.after)
      end
    end
  end
end
