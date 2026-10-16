# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Writes one guarded link: failed on a missing id or target, refused on a
    # self link or a link already there.
    class AddLink < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :refusal, :added

      read "check the ends" do |context|
        context[:problem] = context.work.link_target_problem(context.intent_id, context.target)
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      read "check for a self link or a repeat" do |context|
        context[:refusal] = context.work.link_refusal(context.intent_id, context.target, context.kind)
      end

      gate "%{refusal}", stops: :refusal, pass: ->(context) { context.refusal.nil? }

      step "add the link", done: ->(context) { !context.added.nil? } do |context|
        context[:added] = context.work.add_link(from_ref: context.intent_id, to_ref: context.target, kind: context.kind)
      end

      read "say what was written" do |context|
        context.print("link: #{context.intent_id} #{context.kind} #{context.target}")
      end

      outcome :done, offers: "plastic sync down", because: "the link is on record"
    end
  end
end
