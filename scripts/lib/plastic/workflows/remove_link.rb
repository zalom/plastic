# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Removes one link; fails when no such link exists.
    class RemoveLink < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :removed

      step "remove the link", done: ->(context) { !context.removed.nil? } do |context|
        removed = context.work.remove_link(from_ref: context.intent_id, to_ref: context.target, kind: context.kind)
        context[:removed] = removed
        context[:problem] = removed ? nil : "no #{context.kind} link from #{context.intent_id} to #{context.target}"
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      read "say what was removed" do |context|
        context.print("link: #{context.intent_id} #{context.kind} #{context.target} removed")
      end

      outcome :done, offers: "plastic sync down", because: "the link is gone"
    end
  end
end
