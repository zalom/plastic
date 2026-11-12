# frozen_string_literal: true

require_relative "planning_directive"

module Plastic
  module Graph
    module Work
      # The next concrete action for a delivery, or instructions for the harness.
      class DeliveryAction
        def self.worker_clause(node)
          worker = node.by.to_s
          worker.empty? ? "" : " with its worker #{worker}"
        end

        def self.acting(node) = (yield(node, node.id) if node)

        def initialize(retrieval, intent_id)
          @retrieval = retrieval
          @intent_id = intent_id
        end

        def call
          return [nil, "intent #{@intent_id} is closed", nil] unless @retrieval.intent(@intent_id).open?
          return planning if live.empty?
          return ["plastic intent end #{@intent_id}", "the nodes are done; verify the intent's criteria", nil] if live.all? { |node| node.state == "done" }

          pending_action
        end

        private

        def live = @live ||= @retrieval.nodes(@intent_id).reject { |node| node.state == "removed" }

        def live_in(state) = live.find { |node| node.state == state }

        def planning
          [nil, "the harness must plan this intent", "Before you plan, fetch the architecture map as current as " \
            "possible with an architecture mapping tool such as Enola, or map the code yourself; Plastic runs no tool. " \
            "Read the intent's goal and done criteria. Add work with " \
            "plastic node add #{@intent_id} TITLE --criterion KEY, then add dependencies with plastic edge add. " \
            "Use plastic graph ready #{@intent_id} after the plan is recorded. #{PlanningDirective::TEXT}"]
        end

        def pending_action
          step("release", live_in("failed"), "failed; release it before retrying") ||
            step("claim", @retrieval.ready_nodes(@intent_id).first, "is ready") || waiting_action
        end

        def step(verb, node, reason)
          DeliveryAction.acting(node) { |_, id| ["plastic node #{verb} #{@intent_id} #{id}", "node #{id} #{reason}", nil] }
        end

        def waiting_action = needs_info_action(live_in("needs_info")) || impeded_action(live_in("impeded")) || claimed_action(live_in("claimed")) || blocked_action

        def blocked_action
          [nil, "dependencies block the remaining nodes", "Inspect plastic graph show #{@intent_id} and repair the dependencies " \
            "through edge commands before claiming more work."]
        end

        def needs_info_action(node)
          DeliveryAction.acting(node) do |held, id|
            [nil, "the owner must answer node #{id}", "Ask the owner: #{held.question}. Record the resolution with " \
              "plastic node resolve #{@intent_id} #{id} TEXT."]
          end
        end

        def impeded_action(node)
          DeliveryAction.acting(node) do |held, id|
            [nil, "node #{id} is impeded", "Node #{id} is impeded: #{held.reason}. Clear the impediment, then record the resolution with " \
              "plastic node resolve #{@intent_id} #{id} TEXT."]
          end
        end

        def claimed_action(node)
          DeliveryAction.acting(node) do |held, id|
            [nil, "node #{id} is already claimed", "Continue node #{id}#{DeliveryAction.worker_clause(held)}. " \
              "Record the result with plastic node done #{@intent_id} #{id} TEXT, " \
              "or record a failure with plastic node fail #{@intent_id} #{id} TEXT. #{PlanningDirective::TEXT}"]
          end
        end
      end
    end
  end
end
