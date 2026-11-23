# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/work/repair_regions"

module Plastic
  module Workflows
    module Code
      module Graph
        # Lists the ready nodes of one intent's work graph.
        class Ready < CodeWorkflow
          clear_declarations

          sets :intent, :nodes, :first, :repairs, :repair_id, :repair_state

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          read "list the ready nodes" do |context|
            context[:nodes] = context.retrieval.ready_nodes(context.intent_id)
            context[:first] = context.nodes.first&.id
            context.nodes.each { |node| context.print("ready: #{node.id} #{node.title}") }
            context.data("nodes", node_fields(context))
          end

          read "name the regions to re-plan" do |context|
            structure = context.retrieval.structure
            context[:repairs] = Plastic::Graph::Work::RepairRegions.new(structure.nodes(context.intent_id), structure.edges(context.intent_id)).to_a
            context.repairs.each { |region| context.print(repair_line(region)) }
            context.data("repairs", context.repairs)
          end

          read "name the first region" do |context|
            context[:repair_id], context[:repair_state] = context.repairs.first&.values_at("id", "state")
          end

          def self.repair_line(region)
            waiting = region["downstream"].map { |node| "#{node["id"]} #{node["title"]}" }
            tail = waiting.empty? ? "nothing waits on it" : "waiting on it: #{waiting.join(", ")}"
            "repair: #{region["id"]} #{region["title"]} is #{region["state"]}; #{tail}"
          end

          # The ready nodes as data for a JSON answer: the fields of each and the ids of the nodes it needs.
          def self.node_fields(context)
            needs = context.retrieval.structure.edges(context.intent_id).select { |edge| edge.kind == "needs" }.group_by(&:to)
            context.nodes.map { |node| node_data(node, needs.fetch(node.id, []).map(&:from)) }
          end

          def self.node_data(node, needs)
            node.to_h.slice(:id, :title, :kind, :criterion, :state).transform_keys(&:to_s).merge("needs" => needs)
          end

          outcome :repair, if: ->(context) { context.first.nil? && !context.repairs.empty? }, offers: "plastic node add %{intent_id} TITLE --criterion KEY",
            because: "node %{repair_id} is %{repair_state}; re-plan it and what waits on it"
          outcome :nothing, if: ->(context) { context.first.nil? }, offers: nil, because: "no node is ready to claim"
          outcome :done, offers: "plastic node claim %{intent_id} %{first} --agent NAME", because: "node %{first} is ready"
        end
      end
    end
  end
end
