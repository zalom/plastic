# frozen_string_literal: true

require_relative "lines"

module Plastic
  module Workflows
    # The steps a workflow takes after a node is done: the nodes now ready are named on `ready:` lines, and the next line claims the
    # first of them. With none ready the outcome stays the one the workflow already offers.
    module ReadyAfterDone
      # Prints a `ready:` line for each node now ready of one call and keeps the first one for the next line.
      class NameReady
        def initialize(context) = @context = context

        def call
          ready = @context.retrieval.ready_nodes(@context.intent_id)
          @context[:first_ready] = ready.first&.id
          ready.each { |node| @context.print(Lines.ready_node(node)) }
        end
      end

      def ready_steps
        read("name the nodes now ready") { |context| NameReady.new(context).call }
        outcome :claim_ready, if: ->(context) { context.first_ready }, offers: "plastic node claim %{intent_id} %{first_ready} --agent NAME",
          because: "node %{id} is done; node %{first_ready} is ready"
      end
    end
  end
end
