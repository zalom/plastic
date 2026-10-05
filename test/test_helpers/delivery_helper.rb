# frozen_string_literal: true

module Plastic
  class TestCase
    # Intents at the points of delivery the workflow tests start from.
    module DeliveryHelper
      def specified_intent(spec = "## Done criteria\n- It works\n")
        intent = open_intent
        write("#{intent.dir}/spec.md", "# Spec\n\n#{spec}")
        sync_up
        intent
      end

      # Spec, outcome and one node judged done: nothing stands in the way of the end.
      def ready_intent
        intent = specified_intent
        write("#{intent.dir}/outcome.md", "# Outcome\n\nDelivered.\n")
        sync_up
        work = store_graphs.work
        work.add_node(intent_id: "1", title: "Build")
        work.claim_node(intent_id: "1", id: "n1", by: "a")
        work.done_node(intent_id: "1", id: "n1", judge: "tests", findings: "green")
        intent
      end

      def session_graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)
    end
  end
end
