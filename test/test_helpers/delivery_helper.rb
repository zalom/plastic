# frozen_string_literal: true

module Plastic
  class TestCase
    # Intents at the points of delivery the workflow tests start from.
    module DeliveryHelper
      VERIFICATION = "\n## Verification\n- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n"

      def specified_intent(spec = "## Done criteria\n- It works\n")
        intent = open_intent
        write("#{intent.dir}/spec.md", "# Spec\n\n#{spec}")
        sync_up
        intent
      end

      # Spec, outcome and one node done: nothing stands in the way of the end.
      def ready_intent(verification: VERIFICATION, spec: "## Done criteria\n- It works\n")
        intent = specified_intent(spec)
        write("#{intent.dir}/outcome.md", "# Outcome\n\nDelivered.\n#{verification}")
        sync_up
        work = store_graphs.work
        work.add_node(intent_id: "1", title: "Build", criterion: "It works")
        work.claim_node(intent_id: "1", id: "n1", by: "a")
        work.done_node(intent_id: "1", id: "n1", findings: "green")
        intent
      end

      def session_graphs(session = "s-1") = Plastic::Graph.open(home: @plastic_home, store: "global", session:)
    end
  end
end
