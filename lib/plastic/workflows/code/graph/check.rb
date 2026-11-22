# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/findings"
require_relative "../../../graph/knowledge/store_folder"
require_relative "../../../graph/work/schemas"

module Plastic
  module Workflows
    module Code
      module Graph
        # Prints each finding, or "no findings"; a finding fails the call.
        class Check < CodeWorkflow
          clear_declarations

          HAND_EDIT = "hand edit: no command repairs these findings; edit graph.json by hand, then run plastic sync up and plastic graph check again"

          sets :intent, :findings, :first, :repair

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          read "find problems" do |context|
            context[:findings] = Plastic::Graph::Knowledge::Findings.new(context.retrieval, context.intent_id, schemas: schemas(context)).with_repairs
            context[:repair] = context.findings.filter_map(&:repair).first
            print_findings(context)
          end

          def self.schemas(context)
            folder = Plastic::Graph::Knowledge::StoreFolder.new(context.scope.root)
            Plastic::Graph::Work::Schemas.new(folder, context.intent.dir)
          end

          def self.print_findings(context)
            findings = context.findings
            return context.print("no findings") if findings.empty?

            findings.each do |finding|
              context.print("finding: #{finding.text}")
              context.print("repair: #{finding.repair}") if finding.repair
            end
            context.print(HAND_EDIT) if context.repair.nil?
          end

          gate "see the findings above", stops: :failure, pass: ->(context) { context.findings.empty? || !context.repair.nil? }

          gate "see the findings above", stops: :failure, pass: ->(context) { context.findings.empty? },
            offers: "%{repair}", because: "repair the findings above, then run plastic graph check %{intent_id} again"

          read "find the first ready node" do |context|
            context[:first] = context.retrieval.ready_nodes(context.intent_id).first&.id
          end

          outcome :nothing, if: ->(context) { context.first.nil? }, offers: nil, because: "no node is ready to claim"
          outcome :done, offers: "plastic node claim %{intent_id} %{first}", because: "node %{first} is ready"
        end
      end
    end
  end
end
