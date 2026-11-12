# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Writes the one prose line of a session.
    class WriteNote < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :session_id, :written

      gate "the call names no session; set PLASTIC_SESSION", stops: :failure, pass: ->(context) { !context.session.nil? }

      read "name the session" do |context|
        context[:session_id] = context.session
      end

      step "write the note", done: ->(context) { context.written } do |context|
        context.work.write_note(context.session_id, context.text)
        context[:written] = true
      end

      read "say what was written" do |context|
        context.print("note: #{context.text}")
      end

      outcome :done, offers: "plastic next", because: "session %{session_id} has its note"
    end
  end
end
