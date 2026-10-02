# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Lists the ready nodes of one intent's work graph.
    class ReadyGraph < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent, :nodes, :first

      read "find the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      read "list the ready nodes" do |context|
        context[:nodes] = context.retrieval.ready_nodes(context.intent_id)
        context[:first] = context.nodes.first&.id
        context.nodes.each { |node| context.print("ready: #{node.id} #{node.title}") }
      end

      outcome :done
    end
  end
end
