# frozen_string_literal: true

require_relative "../../code_workflow"
require_relative "../../graph/work/next_pick"
require_relative "../../graph/work/next_offer"

module Plastic
  module Workflows
    module Code
      # Picks the intent this session is working on and offers its next
      # command: the spec, the start, the brief, a failed node, the check or
      # the ready list. Several candidates offer status; none offers a new intent.
      class Next < CodeWorkflow
        clear_declarations
        summary "Picks the intent this session works on and offers its next command."

        sets :next_command, :why, :handoff_text

        read "pick the intent and its next command" do |context|
          pick = Plastic::Graph::Work::NextPick.new(context.retrieval, context.session)
          context[:next_command], context[:why], context[:handoff_text] = Plastic::Graph::Work::NextOffer.new(context.retrieval, pick).call
        end

        outcome :agent_needed, if: ->(context) { !context.handoff_text.nil? }, because: "the next step is the agent's to take"
        outcome :nothing, if: ->(context) { context.next_command.nil? }, offers: "plastic status", because: "%{why}"
        outcome :done, offers: "%{next_command}", because: "%{why}"
      end
    end
  end
end
