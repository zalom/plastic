# frozen_string_literal: true

require_relative "../../routine"
require_relative "../node/add"
require_relative "../node/remove"
require_relative "../node/claim"
require_relative "../node/release"
require_relative "../node/done"
require_relative "../node/fail"
require_relative "../node/ask"
require_relative "../node/impede"
require_relative "../node/resolve"
require_relative "../edge/add"
require_relative "../edge/remove"

module Plastic
  module Commands
    module Intent
      # Prints the goal, the done criteria, the rulings with superseded ones
      # marked, the ready nodes, the main session steps and the usage of the node
      # and edge commands.
      class Brief < Routine
        NODE_AND_EDGE_COMMANDS = [
          Node::Add, Node::Remove, Node::Claim, Node::Release, Node::Done,
          Node::Fail, Node::Ask, Node::Impede, Node::Resolve, Edge::Add, Edge::Remove
        ].freeze

        def self.given_facts = { command_usages: NODE_AND_EDGE_COMMANDS.map(&:usage_line) }

        intent_subject
        reads :work, :knowledge
        workflow :code_show_brief, next: :code_delivery_next
        workflow :code_delivery_next do
          on :done, next: :noop
          on :nothing, next: :noop
          on :agent_needed, next: :agent_advance_delivery
        end
        workflow :agent_advance_delivery, next: :noop
      end
    end
  end
end
