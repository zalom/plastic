# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph"
require_relative "../../../graph/work/lapsed_claims"
require_relative "../../store_names"

module Plastic
  module Workflows
    module Code
      module Graph
        # Lists each lapsed claim of the intents in agent delivery in the named stores, and names the command that
        # restarts the first. It reads the rows and changes no claim.
        class Lapsed < CodeWorkflow
          extend StoreNames

          clear_declarations

          sets :next_command, :why

          read("refuse --stores with --project") { |context| refuse_project(context) }

          read "list the lapsed claims of each agent delivery" do |context|
            claims = store_slugs(context).flat_map { |slug| lapsed_claims(context, slug) }
            claims.each { |claim| context.print(line(claim)) }
            context.data("lapsed", claims.map { |claim| claim.to_h.transform_keys(&:to_s) })
            offer_restart(context, claims.first)
          end

          outcome :nothing, if: ->(context) { context.next_command.nil? }, offers: nil, because: "no agent delivery has a lapsed claim"
          outcome :done, offers: "%{next_command}", because: "%{why}",
            words: "a claim of an agent delivery lapsed, and the next line names the command that takes the first one again"

          def self.lapsed_claims(context, slug)
            retrieval = Plastic::Graph.open(home: context.scope.plastic_home, store: slug, session: context.session, clock: context.clock).retrieval
            Plastic::Graph::Work::LapsedClaims.new(retrieval, store: slug, now: context.now).to_a
          end

          def self.line(claim)
            held = claim.driver? ? "driver" : "node #{claim.node} #{claim.node_title}, agent #{claim.agent || "not recorded"}"
            "lapsed: store #{claim.store}, intent #{claim.intent_id} #{claim.title}, #{held}, session #{claim.session}, " \
              "last renewed #{Plastic.local(claim.last_renewed)}"
          end

          def self.offer_restart(context, claim)
            return unless claim

            command, why = restart(claim)
            context[:next_command] = in_store(context.scope, command, claim.store)
            context[:why] = why
          end

          # The command that takes the lapsed claim again, and why.
          def self.restart(claim)
            id = claim.intent_id
            return ["plastic intent auto #{id}", "the driver claim of intent #{id} lapsed; plastic intent auto #{id} takes it"] if claim.driver?

            node = claim.node
            ["plastic node claim #{id} #{node} --agent #{claim.agent || "NAME"}", "the claim of node #{node} of intent #{id} lapsed; plastic node claim takes it for a new helper"]
          end
        end
      end
    end
  end
end
