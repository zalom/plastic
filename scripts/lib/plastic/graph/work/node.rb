# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # One unit of work inside an intent. The harness picks `kind` and `by`.
      # `criterion` says what done means, `judge` what judged it, `verdict`
      # accept or revise, and `retries` counts the claims.
      #
      #   open -> claimed -> done
      #                   -> failed -> open
      #                   -> parked -> open
      #   open -> removed
      Node = Data.define(:intent_id, :id, :kind, :title, :criterion, :state, :by, :input, :output, :question, :answer,
        :reason, :judge, :verdict, :findings, :retries, :updated_at, :origin_id) do
        include Record

        def refusal(to) = "node #{id} is #{state}; it cannot move to #{to}"

        # An open node that is missing from the intent's ready nodes, because a
        # node it needs is not done.
        def waiting?(ready_nodes) = state == "open" && ready_nodes.none? { |ready| ready.id == id }
      end
      Node::STATES = %w[open claimed done failed parked removed].freeze
      Node::JUDGES = %w[tests tool agent owner].freeze
    end
  end
end
