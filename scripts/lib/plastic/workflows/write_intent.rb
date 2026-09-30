# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Writes a new intent's rows, then prints its folder and store/index.json.
    class WriteIntent < CodeWorkflow
      sets :problem, :intent_id, :printed_paths

      read "check the call" do |c|
        c[:problem] = c.work.intent_problem(parent_id: c.parent_id, ref: c.ref, status: c.status)
      end

      gate "%{problem}", stops: :failure, pass: ->(c) { c.problem.nil? }

      step "write the intent", done: ->(c) { !c.intent_id.nil? } do |c|
        intent = c.work.write_intent(title: c.title, parent_id: c.parent_id, ref: c.ref, kind: c.kind,
          status: c.status, slug: c.slug)
        c[:intent_id] = intent.intent_id
      end

      step "print its files", done: ->(c) { !c.printed_paths.nil? } do |c|
        c[:printed_paths] = c.work.print_intent(c.intent_id)
      end

      read "say what was written" do |c|
        c.print("intent: #{c.intent_id}")
        c.print(c.work.ref_line(c.ref)) if c.ref
        c.printed_paths.each { |path| c.print("printed #{path}") }
      end

      outcome :done, offers: "plastic continue", because: "intent %{intent_id} has its rows and its printed files"
    end
  end
end
